require "test_helper"

class SafeDeploymentTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @member = users(:two)
    @viewer = add_to_fund(create_user("viewer"), @fund, role: "viewer")
    @inactive = add_to_fund(create_user("inactive"), @fund, active: false)
    @outsider = create_user("outsider")
    link_wallet(@admin, :alice)
    link_wallet(@member, :bob)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.code = "0x"
    @chain = Chain::Registry.fetch(SEPOLIA)
    @owners = Chain::Address.sort([ address_of(:alice), address_of(:bob) ])
  end

  teardown { uninstall_fake_rpc }

  # The client's hint for its own deployment transaction, which the chain knows about.
  def report_deploy_hash(hash = "0x#{'a' * 64}")
    @fund.reload
    if @fund.safe_address
      @fake.transactions[hash.downcase] = { hash: hash.downcase, to: @fund.chain.factory, from: nil, input: Chain::Create2.calldata(@fund) }
    end
    patch account_safe_path(@fund), params: { deploy_tx_hash: hash }, as: :json
  end

  SEPOLIA = ChainTestHelper::SEPOLIA

  def intent(**overrides)
    { chain_id: SEPOLIA, token_address: @chain.token.address, owners: @owners, threshold: 2, acknowledge_risk: true }.merge(overrides)
  end

  def configure(**overrides)
    post account_safe_path(@fund), params: intent(**overrides), as: :json
  end

  def make_chain_match
    @fake.code = "0x60"
    @fake.owners = @fund.reload.safe_owners
    @fake.threshold = @fund.safe_threshold
  end

  test "configure returns a deployment the client can recompute" do
    sign_in_as @admin
    configure
    assert_response :created, response.body
    data = json
    assert_equal "draft", data["status"]
    assert_equal SEPOLIA, data["chain_id"]
    assert_equal @owners, data["owners"]
    assert_equal 2, data["threshold"]
    assert_equal @chain.factory, data["factory"]
    assert_equal @chain.singleton, data["singleton"]
    assert_equal @chain.fallback_handler, data["fallback_handler"]
    assert_nil data["deploy_tx_hash"]
    assert_kind_of String, data["salt_nonce"]

    initializer = Chain::Create2.initializer(owners: @owners, threshold: 2, fallback_handler: @chain.fallback_handler)
    assert_equal initializer, data["initializer"]
    assert_equal Chain::Create2.salt_nonce(group_uuid: @fund.reload.safe_group_uuid, chain_id: SEPOLIA).to_s, data["salt_nonce"]
    assert_equal Chain::Create2.predict(factory: @chain.factory, singleton: @chain.singleton, initializer: initializer,
                                        salt_nonce: data["salt_nonce"].to_i), data["safe_address"]
  end

  test "owners are canonicalised" do
    sign_in_as @admin
    configure(owners: @owners.reverse.map { |owner| Chain::Address.checksum(owner) })
    assert_response :created
    assert_equal @owners, json["owners"]
  end

  test "before setup the endpoint shows what can be chosen" do
    sign_in_as @viewer
    get account_safe_path(@fund), as: :json
    assert_response :ok
    assert_equal "draft", json["status"]
    assert_equal [ SEPOLIA ], json["available_chains"].map { |chain| chain["chain_id"] }
  end

  test "only an admin of this fund may configure or record a deployment" do
    { @member => :forbidden, @viewer => :forbidden, @inactive => :not_found, @outsider => :not_found }.each do |user, status|
      sign_in_as user
      configure
      assert_response status, user.name
      report_deploy_hash
      assert_response status, user.name
    end
    assert_nil @fund.reload.safe_address
  end

  test "non-members cannot read and get the same answer as for a missing fund" do
    [ @inactive, @outsider ].each do |user|
      sign_in_as user
      get account_safe_path(@fund), as: :json
      existing = [ response.status, response.body ]
      get account_safe_path(0), as: :json
      assert_equal [ response.status, response.body ], existing
      assert_response :not_found
    end
  end

  test "viewers and members can read" do
    [ @viewer, @member ].each do |user|
      sign_in_as user
      get account_safe_path(@fund), as: :json
      assert_response :ok
    end
  end

  test "owners must be verified wallets of active, signing members" do
    sign_in_as @admin
    configure(owners: [ address_of(:carol), address_of(:alice) ])
    assert_equal "owner_not_verified", json["error"]

    link_wallet(@outsider, :carol)
    configure(owners: [ address_of(:carol), address_of(:alice) ])
    assert_equal "owner_not_verified", json["error"]

    link_wallet(@inactive, :dave)
    configure(owners: [ address_of(:dave), address_of(:alice) ])
    assert_equal "owner_not_verified", json["error"]

    link_wallet(@viewer, :erin)
    configure(owners: [ address_of(:erin), address_of(:alice) ])
    assert_equal "owner_is_viewer", json["error"]

    Wallet.find_by!(address: address_of(:bob)).revoke!
    configure(owners: @owners)
    assert_equal "owner_not_verified", json["error"]

    assert_nil @fund.reload.safe_address
  end

  test "one member cannot hold two owner keys" do
    link_wallet(@admin, :carol)
    sign_in_as @admin
    configure(owners: [ address_of(:alice), address_of(:carol) ], threshold: 2)
    assert_response :unprocessable_entity
    assert_equal "owner_duplicate_member", json["error"]
  end

  test "threshold rules" do
    sign_in_as @admin
    configure(threshold: 0)
    assert_equal "threshold_out_of_range", json["error"]
    configure(threshold: 3)
    assert_equal "threshold_out_of_range", json["error"]
    configure(threshold: "twee")
    assert_equal "threshold_out_of_range", json["error"]
    configure(threshold: nil)
    assert_equal "threshold_out_of_range", json["error"]
    configure(threshold: 2, acknowledge_risk: false)
    assert_equal "risk_not_acknowledged", json["error"]
    configure(threshold: 1, acknowledge_risk: false)
    assert_equal "risk_not_acknowledged", json["error"]
    configure(owners: [ address_of(:alice) ], threshold: 1, acknowledge_risk: false)
    assert_response :created
  end

  test "malformed intent is refused" do
    sign_in_as @admin
    { { owners: [] } => "owners_invalid", { owners: "x" } => "owners_invalid", { owners: nil } => "owners_invalid",
      { owners: [ "0x12" ] } => "invalid_address", { owners: [ @owners[0], @owners[0] ] } => "owners_invalid",
      { owners: [ Chain::Address::SENTINEL ] } => "owners_invalid", { owners: [ Chain::Address::ZERO ] } => "owners_invalid",
      { token_address: "0x12" } => "invalid_address", { token_address: address_of(:alice) } => "token_not_allowed",
      { chain_id: 1 } => "chain_not_enabled", { chain_id: "abc" } => "chain_not_enabled", { chain_id: nil } => "chain_not_enabled",
      { chain_id: 8453 } => "chain_not_enabled", { chain_id: 100 } => "chain_not_enabled" }.each do |bad, code|
      configure(**bad)
      assert_response :unprocessable_entity, bad.to_s
      assert_equal code, json["error"], bad.to_s
    end
  end

  test "malformed JSON gets a JSON answer" do
    sign_in_as @admin
    post account_safe_path(@fund), params: "{niet json", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
    assert_equal "invalid_json", json["error"]
  end

  test "an RPC failure while configuring stores nothing" do
    @fake.fail_with(:block_number)
    sign_in_as @admin
    configure
    assert_response :service_unavailable
    assert_equal "rpc_unavailable", json["error"]
    assert_nil @fund.reload.safe_address
  end

  test "draft can be reconfigured, and the salt stays the fund's" do
    sign_in_as @admin
    configure
    first = json
    configure(owners: [ address_of(:alice) ], threshold: 1)
    assert_response :created
    assert_equal first["salt_nonce"], json["salt_nonce"]
    assert_not_equal first["safe_address"], json["safe_address"]
  end

  test "a transaction hash starts deploying and verification activates" do
    sign_in_as @admin
    configure
    report_deploy_hash("0x#{'A' * 64}")
    assert_response :ok, response.body
    assert_equal "deploying", json["status"]
    assert_equal "0x#{'a' * 64}", json["deploy_tx_hash"]

    make_chain_match
    report_deploy_hash
    assert_equal "active", json["status"]
    assert_predicate json["verified_at"], :present?
    assert_predicate @fund.reload, :safe_active?
    assert_equal "0x#{'a' * 64}", @fund.deploy_tx_hash
  end

  test "malformed deploy hashes are refused and change nothing" do
    sign_in_as @admin
    configure
    [ "0x12", "", nil, 7, "zz" ].each do |bad|
      patch account_safe_path(@fund), params: { deploy_tx_hash: bad }, as: :json
      assert_response :unprocessable_entity, bad.inspect
      assert_equal "invalid_tx_hash", json["error"]
    end
    assert_equal "draft", @fund.reload.safe_status
  end

  test "patch before configure is refused" do
    sign_in_as @admin
    report_deploy_hash
    assert_response :conflict
    assert_equal "safe_not_configured", json["error"]
  end

  test "an identical Safe that already exists is success, without a hash" do
    sign_in_as @admin
    configure
    make_chain_match
    patch account_safe_path(@fund), as: :json
    assert_equal "active", json["status"]
  end

  test "configuring an identical Safe that already exists activates at once" do
    sign_in_as @admin
    @fake.code = "0x60"
    @fake.owners = @owners
    @fake.threshold = 2
    configure
    assert_response :created
    assert_equal "active", json["status"]
  end

  test "after a reverted transaction the Safe that someone else deployed still activates" do
    sign_in_as @admin
    configure
    make_chain_match
    @fake.receipts["0x#{'a' * 64}"] = { status: 0, logs: [] }
    report_deploy_hash
    assert_equal "active", json["status"]
  end

  test "a reverted transaction with no Safe returns to draft" do
    sign_in_as @admin
    configure
    @fake.receipts["0x#{'a' * 64}"] = { status: 0, logs: [] }
    report_deploy_hash
    assert_equal "draft", json["status"]
    assert_equal "deploy_tx_reverted", json["verification_error"]
    assert_nil json["deploy_tx_hash"]
  end

  test "an RPC outage during verification leaves deploying and enqueues the job" do
    sign_in_as @admin
    configure
    @fake.fail_with(:get_code)
    assert_enqueued_with(job: SafeDeploymentVerificationJob, args: [ @fund.id ]) do
      report_deploy_hash
    end
    assert_response :ok
    assert_equal "deploying", json["status"]
  end

  test "settings are locked once deploying, except repeating the same request" do
    sign_in_as @admin
    configure
    report_deploy_hash
    configure(owners: [ address_of(:alice) ], threshold: 1)
    assert_response :conflict
    assert_equal "safe_locked", json["error"]
    configure
    assert_response :created
    assert_equal "deploying", json["status"]
  end

  test "the fund cannot be destroyed through the app once deploying" do
    sign_in_as @admin
    configure
    report_deploy_hash
    assert_no_difference("Account.count") { delete account_path(@fund) }
    assert_match(/kan niet worden verwijderd/, flash[:alert])
  end

  test "live owners in the response show gaps" do
    activate_safe(@fund, owners: @owners, threshold: 2)
    Wallet.find_by!(address: address_of(:bob)).revoke!
    @fake.owners = @owners
    @fake.threshold = 2
    @fake.nonce = 3
    sign_in_as @viewer
    get account_safe_path(@fund), as: :json
    live = json["live"]
    assert live["available"]
    assert_equal "3", live["nonce"]
    alice = live["owners"].find { |row| row["address"] == address_of(:alice) }
    bob = live["owners"].find { |row| row["address"] == address_of(:bob) }
    assert alice["verified_wallet"] && alice["active_member"]
    assert_not bob["verified_wallet"]
    assert_nil bob["name"]
  end

  test "live owners are labelled unavailable during an outage" do
    activate_safe(@fund, owners: @owners, threshold: 2)
    @fake.fail_with(:eth_call)
    sign_in_as @viewer
    get account_safe_path(@fund), as: :json
    assert_response :ok
    assert_equal false, json["live"]["available"]
    assert_equal "rpc_unavailable", json["live"]["error"]
  end
end

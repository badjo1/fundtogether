require "test_helper"

class WalletLinkingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.code = "0x"
    @address = address_of(:alice)
  end

  teardown { uninstall_fake_rpc }

  def challenge(address = @address, purpose: "link")
    post wallet_challenges_path, params: { address: address, purpose: purpose }, as: :json
    assert_response :created, response.body
    json
  end

  test "requires login" do
    post wallet_challenges_path, params: { address: @address, purpose: "link" }, as: :json
    assert_response :unauthorized
    assert_equal "not_authenticated", json["error"]
    post wallets_path, params: { address: @address, nonce: "x", signature: "0x" }, as: :json
    assert_response :unauthorized
    delete wallet_path(1), as: :json
    assert_response :unauthorized
    post wallet_handoffs_path, as: :json
    assert_response :unauthorized
  end

  test "the full linking flow with a real signature" do
    sign_in_as @user
    data = challenge(Chain::Address.checksum(@address))
    assert_equal 32, data["nonce"].length
    message = data["message"]
    assert message.ascii_only?
    assert_includes message, "fundtogether.test wants you to sign in with your Ethereum account:\n#{Chain::Address.checksum(@address)}\n"
    assert_includes message, "URI: https://fundtogether.test/wallets\n"
    assert_includes message, "Version: 1\nChain ID: 11155111\nNonce: #{data['nonce']}\n"
    assert_match(/Issued At: .*\nExpiration Time: /, message)
    assert_includes message, WalletChallenge::STATEMENT

    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, message) }, as: :json
    assert_response :created, response.body
    assert_equal @address, json["address"]

    wallet = @user.wallets.active.find_by!(address: @address)
    assert_equal "eoa", wallet.kind
    assert_predicate wallet.verified_at, :present?
    get wallets_path, as: :json
    assert_equal [ @address ], json["wallets"].map { |row| row["address"] }
  end

  test "the host comes from configuration, never from the request" do
    sign_in_as @user
    post wallet_challenges_path, params: { address: @address, purpose: "link" }, headers: { "HOST" => "evil.example", "X-Forwarded-Host" => "evil.example" }, as: :json
    assert_response :created, response.body
    assert_includes json["message"], "fundtogether.test wants you"
    assert_not_includes json["message"], "evil.example"
  end

  test "a challenge can be used once" do
    sign_in_as @user
    data = challenge
    signature = sign_personal(:alice, data["message"])
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: signature }, as: :json
    assert_response :created
    @user.wallets.active.find_by!(address: @address).revoke!

    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: signature }, as: :json
    assert_response :conflict
    assert_equal "challenge_consumed", json["error"]
    assert_empty @user.wallets.active
  end

  test "an expired challenge is refused" do
    sign_in_as @user
    data = challenge
    travel 11.minutes do
      post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "challenge_expired", json["error"]
  end

  test "another user's challenge is unknown" do
    sign_in_as @user
    data = challenge
    sign_in_as @other
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_response :unprocessable_entity
    assert_equal "challenge_invalid", json["error"]
    assert_empty @other.wallets
  end

  test "a wrong signer is refused and the challenge stays usable" do
    sign_in_as @user
    data = challenge
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:bob, data["message"]) }, as: :json
    assert_response :unprocessable_entity
    assert_equal "wrong_signer", json["error"]
    assert_empty @user.wallets

    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_response :created
  end

  test "a signature over another message is refused" do
    sign_in_as @user
    data = challenge
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, "Iets anders") }, as: :json
    assert_equal "wrong_signer", json["error"]
  end

  test "a challenge for one address cannot link another" do
    sign_in_as @user
    data = challenge
    post wallets_path, params: { address: address_of(:bob), nonce: data["nonce"], signature: sign_personal(:bob, data["message"]) }, as: :json
    assert_equal "challenge_address_mismatch", json["error"]
  end

  test "malformed input is refused" do
    sign_in_as @user
    [ "0x12", "", nil, "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf".sub("7E5F", "7e5F"), [ @address ], { a: 1 } ].each do |bad|
      post wallet_challenges_path, params: { address: bad, purpose: "link" }, as: :json
      assert_response :unprocessable_entity, bad.inspect
      assert_equal "invalid_address", json["error"]
      assert_predicate json["message"], :present?
    end
    [ "handoff", "login", "", nil ].each do |purpose|
      post wallet_challenges_path, params: { address: @address, purpose: purpose }, as: :json
      assert_equal "invalid_purpose", json["error"], purpose.inspect
    end
    data = challenge
    good = sign_personal(:alice, data["message"])
    [ "0x", "0xzz", good[0, 130], "#{good}00", nil, 7, [ good ], high_s_copy(good) ].each do |bad|
      post wallets_path, params: { address: @address, nonce: data["nonce"], signature: bad }, as: :json
      assert_equal "invalid_signature", json["error"], bad.inspect
    end
    [ nil, 7, [ "x" ], "unknown" ].each do |bad|
      post wallets_path, params: { address: @address, nonce: bad, signature: good }, as: :json
      assert_equal "challenge_invalid", json["error"], bad.inspect
    end
  end

  test "v 0/1 from a hardware wallet path is accepted" do
    sign_in_as @user
    data = challenge
    good = sign_personal(:alice, data["message"])
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: good[0, 130] + format("%02x", good[130, 2].to_i(16) - 27) }, as: :json
    assert_response :created
  end

  test "contract addresses are refused at challenge and at linking" do
    sign_in_as @user
    @fake.code = "0x6080"
    post wallet_challenges_path, params: { address: @address, purpose: "link" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "contract_wallet_refused", json["error"]
    assert_match(/Contract-wallets/, json["message"])

    @fake.code = "0x"
    data = challenge
    @fake.code = "0x6080"
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_equal "contract_wallet_refused", json["error"]
    assert_empty @user.wallets
  end

  test "an EIP-7702 delegated EOA still counts as an EOA" do
    sign_in_as @user
    @fake.code = "0xef0100#{'a' * 40}"
    challenge
  end

  test "an RPC failure is an error, not a pass, and the challenge survives" do
    sign_in_as @user
    @fake.fail_with(:get_code)
    post wallet_challenges_path, params: { address: @address, purpose: "link" }, as: :json
    assert_response :service_unavailable
    assert_equal "rpc_unavailable", json["error"]

    @fake.heal!
    data = challenge
    @fake.fail_with(:get_code)
    signature = sign_personal(:alice, data["message"])
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: signature }, as: :json
    assert_response :service_unavailable
    assert_empty @user.wallets

    @fake.heal!
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: signature }, as: :json
    assert_response :created
  end

  test "one active user per address" do
    link_wallet(@other, :alice)
    sign_in_as @user
    data = challenge
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_response :conflict
    assert_equal "wallet_taken", json["error"]
    assert_empty @user.wallets
  end

  test "relinking your own active wallet is harmless" do
    existing = link_wallet(@user, :alice)
    sign_in_as @user
    data = challenge
    post wallets_path, params: { address: @address, nonce: data["nonce"], signature: sign_personal(:alice, data["message"]) }, as: :json
    assert_response :created
    assert_equal existing.id, json["id"]
    assert_equal 1, @user.wallets.count
  end

  test "unlinking is scoped to your own wallets and reports remaining ownership" do
    wallet = link_wallet(@user, :alice)
    other_wallet = link_wallet(@other, :bob)
    @fake.owners = [ @address ]
    activate_safe(accounts(:one), owners: [ @address ], threshold: 1)
    sign_in_as @user

    delete wallet_path(other_wallet), as: :json
    assert_response :not_found
    assert_predicate other_wallet.reload, :active?

    delete wallet_path(wallet), as: :json
    assert_response :ok
    assert_predicate wallet.reload.revoked_at, :present?
    assert_equal [ accounts(:one).id ], json["still_owner_of"].map { |row| row["account_id"] }
    assert_equal true, json["still_owner_of"].first["owner"]

    delete wallet_path(wallet), as: :json
    assert_response :not_found
  end

  test "unlinking works during an outage and says the ownership is unknown" do
    wallet = link_wallet(@user, :alice)
    activate_safe(accounts(:one), owners: [ @address ], threshold: 1)
    @fake.fail_with(:eth_call)
    sign_in_as @user
    delete wallet_path(wallet), as: :json
    assert_response :ok
    assert_nil json["still_owner_of"].first["owner"]
  end

  test "a POST without a CSRF token is refused, in JSON" do
    sign_in_as @user
    ActionController::Base.allow_forgery_protection = true
    post wallet_challenges_path, params: { address: @address, purpose: "link" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_csrf", json["error"]
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "writes are rate limited" do
    sign_in_as @user
    with_counting_rate_limit_store do
      11.times { post wallet_challenges_path, params: { address: @address, purpose: "link" }, as: :json }
    end
    assert_response :too_many_requests
    assert_equal "rate_limited", json["error"]
    assert_match(/Te veel/, json["message"])
  end
end

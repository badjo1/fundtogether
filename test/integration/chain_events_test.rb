require "test_helper"

class ChainEventsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @member = users(:two)
    @viewer = add_to_fund(create_user("viewer"), @fund, role: "viewer")
    @inactive = add_to_fund(create_user("inactive"), @fund, active: false)
    @outsider = create_user("outsider")
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake = install_fake_rpc(FakeRpc.new)
  end

  teardown { uninstall_fake_rpc }

  def record(kind: "token_in", user: nil, finalized: true, amount: 500, index: 0, block: 1060)
    @fund.chain_events.create!(chain_id: @fund.chain_id, tx_hash: "0x#{'a' * 64}", log_index: index, block_number: block,
                               block_hash: "0x#{'b' * 64}", kind: kind, from_address: address_of(:dave), to_address: @fund.safe_address,
                               token_address: @fund.token_address, amount: amount, occurred_at: Time.zone.at(1_700_000_000),
                               finalized: finalized, user: user)
  end

  test "JSON for all roles, newest first, with status and member" do
    record(user: @member, index: 1, block: 1061)
    record(finalized: false, index: 2, block: 1062, amount: (2**256) - 1)
    [ @viewer, @member, @admin ].each do |user|
      sign_in_as user
      get account_chain_events_path(@fund), as: :json
      assert_response :ok
      assert_equal [ 1062, 1061 ], json["events"].map { |row| row["block_number"].to_i }
    end
    assert_equal "in behandeling", json["events"][0]["status"]
    assert_equal ((2**256) - 1).to_s, json["events"][0]["amount"]
    assert_nil json["events"][0]["member"]
    assert_equal "definitief", json["events"][1]["status"]
    assert_equal({ "id" => @member.id, "name" => @member.display_name }, json["events"][1]["member"])
    assert_equal "Inleg", json["events"][1]["label"]
    assert_equal @fund.synced_block.to_s, json["synced_block"]
  end

  test "pagination" do
    51.times { |index| record(index: index, block: 1000 + index) }
    sign_in_as @viewer
    get account_chain_events_path(@fund), as: :json
    assert_equal 50, json["events"].length
    get account_chain_events_path(@fund), params: { page: 2 }, as: :json
    assert_equal 1, json["events"].length
    get account_chain_events_path(@fund), params: { page: "-1; DROP" }
    assert_equal 1, json["page"]
  end

  test "non-members see nothing" do
    record
    [ @inactive, @outsider ].each do |user|
      sign_in_as user
      get account_chain_events_path(@fund, format: :json)
      assert_response :not_found
      get account_chain_events_path(@fund, format: :csv)
      assert_response :not_found
    end
  end

  test "not logged in" do
    get account_chain_events_path(@fund, format: :csv)
    assert_response :unauthorized
  end

  test "CSV for a viewer, with a header and amounts in base units" do
    record(user: @member)
    sign_in_as @viewer
    get account_chain_events_path(@fund, format: :csv)
    assert_response :ok
    assert_match %r{text/csv}, response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    lines = response.body.split("\r\n")
    assert_equal '"datum","soort","status","van","naar","lid","bedrag_basiseenheden","token","tx_hash","log_index","blok"', lines[0]
    assert_includes lines[1], %("500","EURC")
    assert_includes lines[1], %("#{@member.display_name}")
  end

  test "CSV guards against formula injection and quotes" do
    evil = {
      "=HYPERLINK(\"http://x\")" => %("'=HYPERLINK(""http://x"")"),
      "+1+1" => %("'+1+1"), "-1" => %("'-1"), "@SUM(A1)" => %("'@SUM(A1)"), "  =1+1" => %("'=1+1")
    }
    evil.each_with_index do |(name, cell), index|
      user = User.create!(name: name, email_address: "evil#{index}@example.com", password: "password")
      user.update_columns(name: name)
      @fund.account_memberships.create!(user: user, role: "member")
      @fund.chain_events.destroy_all
      record(user: user)
      sign_in_as @viewer
      get account_chain_events_path(@fund, format: :csv)
      assert_includes response.body, cell, name
    end
  end

  test "CSV for a fund without a Safe is refused cleanly" do
    other = accounts(:two)
    add_to_fund(@viewer, other, role: "viewer")
    sign_in_as @viewer
    get account_chain_events_path(other, format: :csv)
    assert_response :conflict
    get account_chain_events_path(other, format: :json)
    assert_response :ok
    assert_empty json["events"]
  end

  test "a sync request is only a hint, by members, for active funds" do
    sign_in_as @member
    tx = "0x#{'D' * 64}"
    assert_enqueued_with(job: ChainSyncJob, args: [ @fund.id, { tx_hash: tx.downcase } ]) do
      assert_no_difference("ChainEvent.count") { post account_sync_requests_path(@fund), params: { tx_hash: tx }, as: :json }
    end
    assert_response :accepted
    assert_enqueued_with(job: ChainSyncJob, args: [ @fund.id, { tx_hash: nil } ]) do
      post account_sync_requests_path(@fund), as: :json
    end
    assert_response :accepted

    [ "0x12", 7, [ "x" ] ].each do |bad|
      post account_sync_requests_path(@fund), params: { tx_hash: bad }, as: :json
      assert_response :unprocessable_entity, bad.inspect
      assert_equal "invalid_tx_hash", json["error"]
    end

    { @viewer => :forbidden, @inactive => :not_found, @outsider => :not_found }.each do |user, status|
      sign_in_as user
      post account_sync_requests_path(@fund), as: :json
      assert_response status, user.name
    end

    @fund.update_columns(safe_status: "deploying")
    sign_in_as @member
    post account_sync_requests_path(@fund), as: :json
    assert_response :conflict
  end

  test "sync requests are rate limited" do
    sign_in_as @member
    with_counting_rate_limit_store do
      11.times { post account_sync_requests_path(@fund), as: :json }
    end
    assert_response :too_many_requests
  end

  test "balance is read live" do
    @fake.balance = 123_456
    sign_in_as @viewer
    get account_balance_path(@fund), as: :json
    assert_response :ok
    assert_equal "live", json["source"]
    assert_equal "123456", json["amount"]
    assert_predicate json["as_of"], :present?
    assert_equal 6, json["token"]["decimals"]
  end

  test "a balance outage never shows zero" do
    @fake.fail_with(:eth_call)
    sign_in_as @viewer
    get account_balance_path(@fund), as: :json
    assert_response :ok
    assert_equal "unavailable", json["source"]
    assert_nil json["amount"]
    assert_predicate json["message"], :present?
  end

  test "a balance outage after a reading is labelled with its time" do
    @fake.balance = 77
    sign_in_as @viewer
    get account_balance_path(@fund), as: :json
    read_at = json["as_of"]
    @fake.fail_with(:eth_call)
    get account_balance_path(@fund), as: :json
    assert_equal "cached", json["source"]
    assert_equal "77", json["amount"]
    assert_equal read_at, json["as_of"]
  end

  test "balance respects membership" do
    [ @inactive, @outsider ].each do |user|
      sign_in_as user
      get account_balance_path(@fund), as: :json
      assert_response :not_found
    end
  end
end

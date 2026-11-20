require "test_helper"

class LowFindingsTest < ActionDispatch::IntegrationTest
  setup do
    @fake = install_fake_rpc(FakeRpc.new)
    @admin = create_user("adminz")
    @fund = Account.create!(name: "Fonds Een")
    add_to_fund(@admin, @fund, role: "admin")
    link_wallet(@admin, :alice)
    activate_safe(@fund, owners: [ address_of(:alice) ], threshold: 1)
    @fake.owners = [ address_of(:alice) ]
    @fake.balance = 10**12
  end

  teardown { uninstall_fake_rpc }

  def event!(**attrs)
    @fund.chain_events.create!({ chain_id: SEPOLIA, tx_hash: "0x#{SecureRandom.hex(32)}", log_index: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990),
                                 occurred_at: Time.current, token_address: @fund.token_address }.merge(attrs))
  end

  # L1
  test "a payout row keeps the name it had when a wallet moves later" do
    bas = add_to_fund(create_user("bas"), @fund)
    cor = add_to_fund(create_user("cor"), @fund)
    wallet = link_wallet(bas, :bob)
    event!(kind: "token_out", from_address: @fund.safe_address, to_address: wallet.address, amount: 1_000_000, user: bas)
    wallet.revoke!
    link_wallet(cor, :bob)
    sign_in_as @admin
    get account_activity_path(@fund)
    assert_match "naar Bas", response.body
    assert_no_match "naar Cor", response.body
  end

  # L3
  test "own contribution is labelled as gross" do
    event!(kind: "token_in", from_address: address_of(:alice), to_address: @fund.safe_address, amount: 300_000_000, user: @admin, finalized: true)
    sign_in_as @admin
    get dashboard_path
    assert_match "vóór uitbetalingen", response.body
  end

  # L4
  test "dot followed by exactly three digits is refused as ambiguous, on both money paths" do
    %w[1.000 12.500 999.999 1.000.000].each do |text|
      assert_raises(Chain::Amount::Invalid, text) { Chain::Amount.parse(text, 6) }
    end
    assert_match "Bedoel je", (Chain::Amount.parse("1.000", 6) rescue $!.message)
    { "0.001" => 1_000, "0.75" => 750_000, "1.5" => 1_500_000, "1,000" => 1_000_000, "1,5" => 1_500_000, "1.0000" => 1_000_000, "1000" => 1_000_000_000 }.each do |text, units|
      assert_equal units, Chain::Amount.parse(text, 6), text
    end
    sign_in_as @admin
    post account_proposal_pages_path(@fund), params: { kind: "transfer_token", title: "x", recipient_choice: "other", recipient: address_of(:dave), amount: "1.000" }
    assert_response :unprocessable_entity
    assert_match "Bedoel je", response.body
    assert_equal 0, @fund.safe_proposals.count
  end

  test "the form echoes the amount as it will be read" do
    sign_in_as @admin
    get new_account_proposal_page_path(@fund, kind: "transfer_token")
    assert_select "[data-controller~=amount-echo]"
    assert_select "[data-amount-echo-target=output]"
    get account_contribute_path(@fund)
    assert_select "[data-controller~=amount-echo]"
  end

  # L5
  test "login without a password is a refused login, not a 500" do
    post session_path, params: { email_address: @admin.email_address }
    assert_redirected_to new_session_path
    post session_path, params: { password: "x" }
    assert_redirected_to new_session_path
    post session_path, params: { email_address: { a: 1 }, password: [ "x" ] }
    assert_redirected_to new_session_path
  end

  test "NUL bytes in any parameter are a 400, not a 500" do
    post session_path, params: { email_address: "a\u0000b@example.com", password: "x" }
    assert_response :bad_request
    post register_path, params: { user: { name: "Na\u0000me", email_address: "x@example.com", password: "password", password_confirmation: "password" } }
    assert_response :bad_request
    sign_in_as @admin
    get account_activity_path(@fund, member: "1\u0000")
    assert_response :bad_request
  end

  test "absurd page numbers and bad filters are answered" do
    sign_in_as @admin
    get account_activity_path(@fund, page: "99999999999999999999999")
    assert_response :success
    get account_chain_events_path(@fund, page: "99999999999999999999999"), as: :json
    assert_response :success
    get account_activity_path(@fund, member: "99999999999999999999999")
    assert_response :success
    get account_activity_path(@fund, member: [ "1" ], page: [ "2" ])
    assert_response :success
    get account_chain_events_path(@fund, page: [ "2" ]), as: :json
    assert_response :success
    get list_account_proposal_pages_path(@fund, page: "-1")
    assert_response :success
  end

  # L6
  test "a member who unlinked an owner key cannot become an owner with a second key" do
    bas = add_to_fund(create_user("bas"), @fund)
    old = link_wallet(bas, :bob)
    @fake.owners = [ address_of(:alice), old.address ]
    old.revoke!
    link_wallet(bas, :carol)
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "add_owner", title: "Tweede sleutel", params: { owner: address_of(:carol), threshold: "1" }, acknowledge_risk: true }, as: :json
    assert_equal "owner_duplicate_member", json["error"]
    # Replacing the lost key is the honest route, and stays open.
    post account_proposals_path(@fund), params: { kind: "swap_owner", title: "Nieuwe sleutel", params: { old_owner: old.address, new_owner: address_of(:carol) } }, as: :json
    assert_response :created
  end

  # L8
  test "CSV prefixes a formula hidden after a separator" do
    assert_equal %("'x;=1+1"), Chain::CsvExport.cell("x;=1+1")
    assert_equal %("'a,@SUM(1)"), Chain::CsvExport.cell("a,@SUM(1)")
    assert_equal %("Bas Jansen"), Chain::CsvExport.cell("Bas Jansen")
    assert_equal %("2026-11-09T05:47:48Z"), Chain::CsvExport.cell("2026-11-09T05:47:48Z")
  end

  # L9
  test "unused engines are not loaded" do
    routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_empty routes.grep(%r{/rails/(active_storage|action_mailbox|conductor)})
    assert_not defined?(ActiveStorage::Blob)
    assert_not defined?(ActionMailbox::InboundEmail)
  end

  # L10
  test "a fund description has a length limit" do
    sign_in_as @admin
    patch settings_path, params: { account_id: @fund.id, account: { description: "x" * 2_001 } }
    assert_response :unprocessable_entity
  end

  # L11
  test "blocked syncs are discarded instead of piling up" do
    assert_equal :discard, ChainSyncJob.concurrency_on_conflict
  end

  # L12 is in identity_and_logging_test.rb (the handoff page names the account's email).

  # H5
  test "the transparency page publishes the viem hash and the residual risk" do
    sign_in_as @admin
    get account_transparency_path(@fund)
    assert_match Rails.configuration.x.viem_sha256, response.body
    assert_match "Wat FundTogether niet kan uitsluiten", response.body
  end

  test "the published viem hash matches the file served" do
    assert_equal Digest::SHA256.file(Rails.root.join("vendor/javascript/viem.js")).hexdigest, Rails.configuration.x.viem_sha256
  end

  test "the signing page explains the independent check, prefilled for this proposal" do
    sign_in_as @admin
    post account_proposals_path(@fund), params: { kind: "transfer_token", title: "x", params: { recipient: address_of(:dave), amount: "1" } }, as: :json
    proposal = SafeProposal.find(json["id"])
    get account_proposal_page_path(@fund, proposal)
    assert_includes response.body, proposal.safe_tx_hash
    assert_match "cast call", response.body
    assert_includes response.body, "getTransactionHash"
    assert_match "hardware wallet", response.body
    assert_select "[data-testid=independent-check]"
  end

  test "importmap tags carry subresource integrity" do
    get root_path
    assert_match(/"integrity":\s*\{/, response.body)
  end
end

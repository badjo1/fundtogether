require "test_helper"

# M11, M12, M7: the screen never says something the chain does not.
class ProposalHonestyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @owner = users(:two)
    link_wallet(@admin, :alice)
    link_wallet(@owner, :bob)
    @owners = [ address_of(:alice), address_of(:bob) ]
    activate_safe(@fund, owners: @owners, threshold: 2)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.owners = @owners.dup
    @fake.threshold = 2
    @fake.nonce = 5
    @recipient = address_of(:dave)
    sign_in_as @admin
  end

  teardown { uninstall_fake_rpc }

  def proposal(kind: "transfer_token", amount: "5000000", signed: true)
    post account_proposals_path(@fund), params: { kind: kind, title: "Te veel", params: { recipient: @recipient, amount: amount } }, as: :json
    assert_response :created, response.body
    row = SafeProposal.find(json["id"])
    if signed
      { alice: @admin, bob: @owner }.each { |key, user| row.safe_signatures.create!(signer_address: address_of(key), signature: sign_hash(key, row.safe_tx_hash), user: user) }
    end
    row
  end

  test "over-balance token payout with enough signatures is not ready, and says why" do
    @fake.balance = 1
    row = proposal
    get account_proposal_path(@fund, row), as: :json
    assert_equal false, json["live"]["executable"]
    assert_equal "insufficient_balance", json["live"]["reason"]
    assert_includes json["live"]["warnings"], "insufficient_balance"

    get live_account_proposal_page_path(@fund, row)
    assert_select "[data-testid=insufficient-balance]"
    assert_select "#uitvoeren-titel", count: 0
    assert_select "form[action=?]", reject_account_proposal_page_path(@fund, row)
    assert_select "form[action=?]", cancel_account_proposal_page_path(@fund, row)
    assert_match "Te weinig saldo", response.body
  end

  test "over-balance native payout is judged against ETH, not the token" do
    @fake.balance = 10**12
    @fake.native_balance = 1
    get account_proposal_path(@fund, proposal(kind: "transfer_native", amount: "1000")), as: :json
    assert_equal "insufficient_balance", json["live"]["reason"]
  end

  test "enough balance reads ready, and it follows the balance live" do
    @fake.balance = 5_000_000
    row = proposal
    get account_proposal_path(@fund, row), as: :json
    assert json["live"]["executable"]
    @fake.balance = 4_999_999
    get account_proposal_path(@fund, row), as: :json
    assert_not json["live"]["executable"]
  end

  test "a balance that cannot be read never reads ready" do
    @fake.balance = 5_000_000
    row = proposal
    @fake.define_singleton_method(:eth_call) do |to:, data:|
      raise Chain::Rpc::Unavailable, "kapot" if data.start_with?(Chain::Abi.selector_hex(Chain::Abi::SELECTORS.fetch(:balance_of)))

      super(to: to, data: data)
    end
    get account_proposal_path(@fund, row), as: :json
    assert_not json["live"]["executable"]
    assert_equal "balance_unknown", json["live"]["reason"]
  end

  test "owner changes and rejections do not depend on a balance" do
    @fake.balance = 0
    post account_proposals_path(@fund), params: { kind: "change_threshold", title: "x", params: { threshold: "1" }, acknowledge_risk: true }, as: :json
    assert_response :created
    assert_not_includes json["live"]["warnings"], "insufficient_balance"
    assert_nil @fake.calls.tally[:get_balance]
  end

  test "a list of open proposals reads the balance once" do
    @fake.balance = 10
    3.times { |i| proposal(amount: (i + 1).to_s, signed: false) }
    @fake.calls.clear
    get list_account_proposal_pages_path(@fund)
    assert_response :success
    assert_operator @fake.calls.count(:eth_call), :<=, 4, "owners, threshold, nonce, one balanceOf"
  end

  # --- M7

  test "removing an owner added after deployment warns, from live owners" do
    late = add_to_fund(create_user("laat"), @fund)
    link_wallet(late, :carol)
    @fake.owners = @owners + [ address_of(:carol) ]
    delete user_path(late), params: { account_id: @fund.id }
    assert_match "kan op de blockchain nog steeds goedkeuren", flash[:warning]
    assert_redirected_to new_account_proposal_page_path(@fund, kind: "remove_owner", owner: address_of(:carol))
  end

  test "removing an owner who unlinked first still warns" do
    late = add_to_fund(create_user("laat"), @fund)
    wallet = link_wallet(late, :carol)
    wallet.revoke!
    @fake.owners = @owners + [ address_of(:carol) ]
    delete user_path(late), params: { account_id: @fund.id }
    assert_match "kan op de blockchain nog steeds goedkeuren", flash[:warning]
    assert_redirected_to new_account_proposal_page_path(@fund, kind: "remove_owner", owner: address_of(:carol))
  end

  test "removing someone who is no owner gives plain success" do
    other = add_to_fund(create_user("lid"), @fund)
    link_wallet(other, :carol)
    delete user_path(other), params: { account_id: @fund.id }
    assert_nil flash[:warning]
    assert_match "geen lid meer", flash[:notice]
  end

  test "when the chain cannot be read, removal says the check could not be done" do
    other = add_to_fund(create_user("lid"), @fund)
    @fake.fail_with(:all)
    delete user_path(other), params: { account_id: @fund.id }
    assert_match "konden niet controleren", flash[:warning]
    assert_not @fund.active_users.exists?(other.id)
  end

  # --- M12

  test "the balance frame shows ETH next to the token when there is any" do
    @fake.balance = 0
    @fake.native_balance = 1_800_000_000_000_000
    get account_live_balance_path(@fund)
    assert_match "0,00 EURC", response.body
    assert_match "0,0018 ETH", response.body
  end

  test "the balance frame stays quiet about ETH when there is none, and JSON has both" do
    @fake.balance = 7
    get account_live_balance_path(@fund)
    assert_no_match(/ ETH</, response.body)
    @fake.native_balance = 42
    get account_balance_path(@fund), as: :json
    assert_equal "42", json["native_amount"]
    assert_equal "7", json["amount"]
  end

  test "a native payout shows amount and recipient in activity and CSV, labelled as from the proposal" do
    row = proposal(kind: "transfer_native", amount: "100000000000000", signed: false)
    @fund.chain_events.create!(chain_id: SEPOLIA, tx_hash: "0x#{'c' * 64}", log_index: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990),
                               kind: "execution_success", safe_tx_hash: row.safe_tx_hash, safe_proposal_id: row.id, occurred_at: Time.current)
    get account_activity_path(@fund)
    assert_match "0,0001 ETH", response.body
    assert_match Chain::Address.checksum(@recipient), response.body
    assert_match "uit het voorstel", response.body

    get account_chain_events_path(@fund, format: :csv)
    line = response.body.lines.find { |entry| entry.include?("0x#{'c' * 64}") }
    assert_includes line, @recipient
    assert_includes line, "100000000000000"
  end

  test "an execution with no known proposal says what we do not know" do
    @fund.chain_events.create!(chain_id: SEPOLIA, tx_hash: "0x#{'d' * 64}", log_index: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990),
                               kind: "execution_success", safe_tx_hash: "0x#{'e' * 64}", occurred_at: Time.current)
    get account_activity_path(@fund)
    assert_match "Buiten FundTogether uitgevoerd", response.body
  end
end

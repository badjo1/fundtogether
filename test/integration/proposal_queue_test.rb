require "test_helper"

# H1: a member without signing power cannot jam a fund. See docs/ARCHITECTURE.md, Nonce and queue rules.
class ProposalQueueTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @owner = users(:two)
    @griefer = add_to_fund(create_user("griefer"), @fund)
    link_wallet(@admin, :alice)
    link_wallet(@owner, :bob)
    link_wallet(@griefer, :carol)
    @owners = [ address_of(:alice), address_of(:bob) ]
    activate_safe(@fund, owners: @owners, threshold: 2)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.owners = @owners.dup
    @fake.threshold = 2
    @fake.nonce = 5
    @fake.balance = 1_000_000_000
    @fake.native_balance = 10**18
    @recipient = address_of(:dave)
  end

  teardown { uninstall_fake_rpc }

  def propose(kind: "transfer_token", title: "Uitbetaling", params: nil, amount: "1000000", **rest)
    params ||= { recipient: @recipient, amount: amount }
    post account_proposals_path(@fund), params: { kind: kind, title: title, params: params }.merge(rest), as: :json
  end

  def propose!(**args)
    propose(**args)
    assert_response :created, response.body
    SafeProposal.find(json["id"])
  end

  def signed_by(proposal, key, user)
    proposal.safe_signatures.create!(signer_address: address_of(key), signature: sign_hash(key, proposal.safe_tx_hash), user: user)
    proposal
  end

  # --- nonce rules

  test "a member without signing power never claims a nonce beyond the next" do
    sign_in_as @griefer
    nonces = 5.times.map { |i| propose!(amount: (i + 1).to_s).nonce.to_i }
    assert_equal [ 5 ] * 5, nonces
  end

  test "the griefing reproduction: junk does not push real work back or block an owner change" do
    sign_in_as @griefer
    5.times { |i| propose!(amount: (i + 1).to_s) }

    sign_out
    sign_in_as @admin
    assert_equal 5, propose!(amount: "777").nonce.to_i, "unsigned junk holds no slot, so the admin competes at the live nonce"
    remove = propose!(kind: "remove_owner", title: "Weg", params: { owner: address_of(:bob), threshold: "1" }, acknowledge_risk: true)
    assert_equal 5, remove.nonce.to_i
  end

  test "owners keep an ordered queue: their own and signed proposals hold a slot, unsigned junk does not" do
    sign_in_as @griefer
    junk = propose!(amount: "1")
    sign_out
    sign_in_as @admin
    first = propose!(amount: "2")
    second = propose!(amount: "3")
    assert_equal [ 5, 5, 6 ], [ junk.nonce.to_i, first.nonce.to_i, second.nonce.to_i ]
  end

  test "a member's proposal an owner has signed holds its slot" do
    sign_in_as @griefer
    useful = propose!(amount: "1")
    signed_by(useful, :bob, @owner)
    sign_out
    sign_in_as @admin
    assert_equal 6, propose!(amount: "2").nonce.to_i
  end

  test "owner changes always take the live nonce, whatever is queued" do
    sign_in_as @admin
    3.times { |i| propose!(amount: (i + 1).to_s) }
    change = propose!(kind: "change_threshold", title: "Eén handtekening", params: { threshold: "1" }, acknowledge_risk: true)
    assert_equal 5, change.nonce.to_i
  end

  test "a junk owner change cannot block a real one: both compete at the live nonce and one supersedes the other" do
    sign_in_as @griefer
    junk = propose!(kind: "change_threshold", title: "Junk", params: { threshold: "1" }, acknowledge_risk: true)
    sign_out
    sign_in_as @admin
    real = propose!(kind: "remove_owner", title: "Bob eruit", params: { owner: address_of(:bob), threshold: "1" }, acknowledge_risk: true)
    assert_equal junk.nonce, real.nonce
    assert_includes json["live"]["warnings"], "sibling_at_same_nonce"
  end

  # --- caps

  test "a member's open proposals are capped" do
    sign_in_as @griefer
    Chain::ProposalCreator::OPEN_PER_MEMBER.times { |i| propose!(amount: (i + 1).to_s) }
    propose(amount: "999")
    assert_response :too_many_requests
    assert_equal "too_many_open_proposals", json["error"]
    propose(kind: "change_threshold", params: { threshold: "1" }, acknowledge_risk: true)
    assert_equal "too_many_open_proposals", json["error"], "a member cannot flood owner changes either"
  end

  test "the fund's queue is capped for members, but an owner's payout and any owner change still go in" do
    group = 6.times.map { |i| add_to_fund(create_user("lid#{i}"), @fund) }
    group.each_with_index do |member, m|
      sign_out
      sign_in_as member
      Chain::ProposalCreator::OPEN_PER_MEMBER.times { |i| propose!(amount: "#{m + 1}#{i + 1}") }
    end
    assert_equal Chain::ProposalCreator::OPEN_PER_FUND, @fund.safe_proposals.open.count

    sign_out
    sign_in_as @griefer
    propose(amount: "999")
    assert_response :too_many_requests
    assert_equal "fund_queue_full", json["error"]

    sign_out
    sign_in_as @admin
    propose!(amount: "1234")
    propose!(kind: "remove_owner", title: "Weg", params: { owner: address_of(:bob), threshold: "1" }, acknowledge_risk: true)
  end

  test "an admin who is not an owner can always propose an owner change, even above the member cap" do
    @fake.owners = [ address_of(:bob), address_of(:erin) ]
    sign_in_as @admin
    Chain::ProposalCreator::OPEN_PER_MEMBER.times { |i| propose!(amount: (i + 1).to_s) }
    propose(amount: "999")
    assert_equal "too_many_open_proposals", json["error"]
    propose!(kind: "remove_owner", title: "Erin eruit", params: { owner: address_of(:erin), threshold: "1" }, acknowledge_risk: true)
  end

  test "a passed proposal does not count against the cap" do
    sign_in_as @griefer
    Chain::ProposalCreator::OPEN_PER_MEMBER.times { |i| propose!(amount: (i + 1).to_s) }
    @fake.nonce = 6
    propose!(amount: "999")
  end

  # --- cancel

  test "the proposer cancels their own unsigned proposal, and it stops counting and cannot be signed" do
    sign_in_as @griefer
    proposal = propose!
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :success
    assert_equal "cancelled", json["state"]
    assert_equal @griefer, proposal.reload.cancelled_by
    assert_not_nil proposal.cancelled_at

    sign_out
    sign_in_as @owner
    post account_proposal_signatures_path(@fund, proposal), params: { signature: sign_hash(:bob, proposal.safe_tx_hash) }, as: :json
    assert_equal "proposal_not_open", json["error"]
  end

  test "an admin cancels anyone's proposal; another member cannot" do
    sign_in_as @griefer
    proposal = propose!
    sign_out
    sign_in_as @owner
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :forbidden
    assert proposal.reload.open?
    sign_out
    sign_in_as @admin
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :success
  end

  test "a proposer cannot cancel what someone else signed, an admin can, and the page says signatures stay valid" do
    sign_in_as @griefer
    proposal = signed_by(propose!, :bob, @owner)
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :forbidden
    assert_equal "cancel_signed_needs_admin", json["error"]

    sign_out
    sign_in_as @admin
    post cancel_account_proposal_page_path(@fund, proposal)
    assert_redirected_to account_proposal_page_path(@fund, proposal)
    assert_match "blijven geldig", flash[:warning]
    assert_equal "cancelled", proposal.reload.state
  end

  test "a cancelled proposal with signatures can still be rejected, and the page offers it" do
    sign_in_as @admin
    proposal = signed_by(propose!, :bob, @owner)
    post cancel_account_proposal_page_path(@fund, proposal)
    get live_account_proposal_page_path(@fund, proposal)
    assert_select "form[action=?]", reject_account_proposal_page_path(@fund, proposal)
    post reject_account_proposal_page_path(@fund, proposal)
    rejection = @fund.safe_proposals.where(kind: "rejection").last
    assert_equal proposal.nonce, rejection.nonce

    unsigned = propose!(amount: "77")
    post cancel_account_proposal_page_path(@fund, unsigned)
    post reject_account_proposal_page_path(@fund, unsigned)
    assert_match "geen voorstel open", flash[:alert]
  end

  test "a viewer and an outsider cannot cancel" do
    sign_in_as @griefer
    proposal = propose!
    viewer = add_to_fund(create_user("kijker"), @fund, role: "viewer")
    sign_out
    sign_in_as viewer
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :forbidden
    sign_out
    sign_in_as create_user("buiten")
    delete account_proposal_path(@fund, proposal), as: :json
    assert_response :not_found
  end

  test "an identical proposal can be made again after cancelling" do
    sign_in_as @admin
    first = propose!
    delete account_proposal_path(@fund, first), as: :json
    second = propose!
    assert_equal first.safe_tx_hash, second.safe_tx_hash
    assert_not_equal first.id, second.id
  end

  test "sync does not reopen a cancelled proposal, but a real execution still shows" do
    sign_in_as @admin
    cancelled = propose!
    delete account_proposal_path(@fund, cancelled), as: :json
    Chain::ProposalReconciler.new(@fund).call(chain_nonce: 5)
    assert_equal "cancelled", cancelled.reload.state
    Chain::ProposalReconciler.new(@fund).call(chain_nonce: 6)
    assert_equal "cancelled", cancelled.reload.state

    # Signatures made before cancelling stay valid on-chain, so the chain can overrule the app.
    @fund.chain_events.create!(chain_id: SEPOLIA, tx_hash: "0x#{'c' * 64}", log_index: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990),
                               kind: "execution_success", safe_tx_hash: cancelled.safe_tx_hash, occurred_at: Time.current)
    Chain::ProposalReconciler.new(@fund).call(chain_nonce: 6)
    assert_equal "executed", cancelled.reload.state
  end

  test "removing a member cancels their open proposals" do
    sign_in_as @griefer
    3.times { |i| propose!(amount: (i + 1).to_s) }
    sign_out
    sign_in_as @admin
    delete user_path(@griefer), params: { account_id: @fund.id }
    assert_equal 0, @fund.safe_proposals.open.where(proposer: @griefer).count
    assert_equal 3, @fund.safe_proposals.where(proposer: @griefer, state: "cancelled", cancelled_by: @admin).count
  end

  test "leaving a fund cancels your open proposals" do
    sign_in_as @griefer
    propose!
    delete leave_account_path(@fund)
    assert_equal 0, @fund.safe_proposals.open.where(proposer: @griefer).count
  end

  # --- gap after a cancel

  test "a proposal left behind a cancelled nonce says so and can be made again at the free nonce" do
    sign_in_as @admin
    first = propose!(amount: "1")
    second = propose!(amount: "2")
    assert_equal 6, second.nonce.to_i
    delete account_proposal_path(@fund, first), as: :json
    get account_proposal_path(@fund, second), as: :json
    assert_includes json["live"]["warnings"], "nonce_gap"

    post renumber_account_proposal_page_path(@fund, second)
    replacement = @fund.safe_proposals.open.order(:id).last
    assert_equal "cancelled", second.reload.state
    assert_equal 5, replacement.nonce.to_i
    assert_equal second.params, replacement.params
    assert_redirected_to account_proposal_page_path(@fund, replacement)
  end

  test "the reproduction's end state: after removal a fund is clean and works" do
    sign_in_as @griefer
    5.times { |i| propose!(amount: (i + 1).to_s) }
    sign_out
    sign_in_as @admin
    delete user_path(@griefer), params: { account_id: @fund.id }
    assert_equal 0, @fund.safe_proposals.open.count
    assert_equal 5, propose!.nonce.to_i
  end

  # --- pages

  test "the proposal page offers cancel to the proposer and an admin, not to others" do
    sign_in_as @griefer
    proposal = propose!
    get live_account_proposal_page_path(@fund, proposal)
    assert_select "form[action=?]", cancel_account_proposal_page_path(@fund, proposal)
    sign_out
    sign_in_as @owner
    get live_account_proposal_page_path(@fund, proposal)
    assert_select "form[action=?]", cancel_account_proposal_page_path(@fund, proposal), count: 0
    sign_out
    sign_in_as @admin
    post cancel_account_proposal_page_path(@fund, proposal)
    get live_account_proposal_page_path(@fund, proposal)
    assert_match "Ingetrokken", response.body
    get list_account_proposal_pages_path(@fund)
    assert_match "Ingetrokken", response.body
  end
end

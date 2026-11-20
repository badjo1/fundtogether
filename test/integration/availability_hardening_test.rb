require "test_helper"

# H4, M3, M4, M10, M9: what one person can make the app spend, and what a stale click or a lagging node can do.
class AvailabilityHardeningTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  S = "0x1111111111111111111111111111111111111111".freeze

  setup do
    @fund = accounts(:one)
    @admin = users(:one)
    @member = users(:two)
    link_wallet(@admin, :alice)
    link_wallet(@member, :bob)
    @owners = [ address_of(:alice), address_of(:bob) ]
    activate_safe(@fund, owners: @owners, threshold: 2, safe: S)
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.owners = @owners.dup
    @fake.threshold = 2
    @fake.nonce = 5
    @fake.balance = 10**12
    @fake.native_balance = 10**18
    @fake.code = "0x"
  end

  teardown { uninstall_fake_rpc }

  def stored_proposal(nonce:, state: "open", amount: 1)
    params = { "recipient" => address_of(:dave), "amount" => amount.to_s }
    data = Chain::ProposalBuilder.build(kind: "transfer_token", params: params, safe: S, token: @fund.token_address, owners: @owners, threshold: 2, current_nonce: 0).data
    hash = Chain::Eip712.safe_tx_hash(chain_id: SEPOLIA, safe: S, to: @fund.token_address, value: 0, data: data, operation: 0, nonce: nonce)
    @fund.safe_proposals.create!(proposer: @admin, kind: "transfer_token", title: "P#{nonce}", params: params, to: @fund.token_address, value: 0, data: data,
                                 operation: 0, nonce: nonce, safe_tx_hash: hash, state: state)
  end

  def sign!(proposal, key, user)
    proposal.safe_signatures.create!(signer_address: address_of(key), signature: sign_hash(key, proposal.safe_tx_hash), user: user)
  end

  def count_recoveries
    count = 0
    original = Chain::Signature.method(:recover_point)
    Chain::Signature.singleton_class.send(:define_method, :recover_point) { |*args| count += 1; original.call(*args) }
    yield
    count
  ensure
    Chain::Signature.singleton_class.send(:define_method, :recover_point, original)
    Chain::Signature.singleton_class.send(:private, :recover_point)
  end

  # --- H4

  test "a signature recovers once: at receipt, or the first read of an older row, then never again" do
    row = stored_proposal(nonce: 5)
    sign!(row, :alice, @admin)
    sign_in_as @member
    assert_equal 1, count_recoveries { get account_proposal_path(@fund, row), as: :json }
    assert_equal 0, count_recoveries { get account_proposal_path(@fund, row), as: :json }
    assert_equal [ address_of(:alice) ], json["live"]["valid_signers"]
  end

  test "signing stores the verification, so the next read does not recover" do
    row = stored_proposal(nonce: 5)
    sign_in_as @member
    post account_proposal_signatures_path(@fund, row), params: { signature: sign_hash(:bob, row.safe_tx_hash) }, as: :json
    assert_response :created
    assert_not_nil row.safe_signatures.first.verification_mac
    assert_equal 0, count_recoveries { get account_proposal_path(@fund, row), as: :json }
  end

  test "a stored verification does not outlive the owner: live owners decide on every read" do
    row = stored_proposal(nonce: 5)
    sign!(row, :alice, @admin)
    sign_in_as @member
    get account_proposal_path(@fund, row), as: :json
    @fake.owners = [ address_of(:bob) ]
    get account_proposal_path(@fund, row), as: :json
    assert_empty json["live"]["valid_signers"]
    assert_equal [ address_of(:alice) ], json["live"]["stale_signers"]
  end

  test "a row changed in the database does not pass on its stored verification" do
    row = stored_proposal(nonce: 5)
    signature = sign!(row, :alice, @admin)
    sign_in_as @member
    get account_proposal_path(@fund, row), as: :json
    SafeSignature.where(id: signature.id).update_all(signer_address: address_of(:bob))
    get account_proposal_path(@fund, row), as: :json
    assert_empty json["live"]["valid_signers"]
  end

  test "lists and frames do not recover closed proposals at all" do
    30.times { |i| sign!(stored_proposal(nonce: i + 100, state: "executed"), :alice, @admin) }
    open = stored_proposal(nonce: 5)
    sign!(open, :alice, @admin)
    sign_in_as @member
    assert_equal 1, count_recoveries { get list_account_proposal_pages_path(@fund) }
    assert_equal 0, count_recoveries { get account_live_attention_path(@fund) }
  end

  test "the list and the JSON index are paginated" do
    60.times { |i| stored_proposal(nonce: i, state: "superseded") }
    sign_in_as @member
    get list_account_proposal_pages_path(@fund)
    assert_select "li", ProposalView::CLOSED_PAGE_SIZE
    assert_select "a", text: "Ouder"
    get list_account_proposal_pages_path(@fund, page: 3)
    assert_select "li", 60 - (2 * ProposalView::CLOSED_PAGE_SIZE)
    get account_proposals_path(@fund), as: :json
    assert_equal SafeProposalsController::PAGE_SIZE, json["proposals"].size
    assert_equal 2, json["next_page"]
    get account_proposals_path(@fund, page: 99_999_999_999_999), as: :json
    assert_response :success
  end

  test "expensive frames are rate limited and answer with a frame" do
    sign_in_as @member
    with_counting_rate_limit_store do
      61.times { get account_live_attention_path(@fund) }
      assert_response :too_many_requests
      assert_select "turbo-frame#attention"
      61.times { get list_account_proposal_pages_path(@fund) }
      assert_response :too_many_requests
      assert_select "turbo-frame#proposal_list"
      31.times { get account_proposals_path(@fund), as: :json }
      assert_response :too_many_requests
    end
  end

  # --- M3

  def configured_draft
    fund = Account.create!(name: "Nieuw fonds")
    add_to_fund(@admin, fund, role: "admin")
    salt = Chain::Create2.salt_nonce(group_uuid: fund.reload.safe_group_uuid, chain_id: SEPOLIA)
    chain = Chain::Registry.fetch(SEPOLIA)
    init = Chain::Create2.initializer(owners: @owners, threshold: 2, fallback_handler: chain.fallback_handler)
    address = Chain::Create2.predict(factory: chain.factory, singleton: chain.singleton, initializer: init, salt_nonce: salt)
    fund.update!(chain_id: SEPOLIA, token_address: chain.token.address, safe_address: address, safe_salt_nonce: salt, safe_owners: @owners, safe_threshold: 2, synced_block: 1)
    fund
  end

  def deploy_tx(fund, to: nil, input: nil)
    chain = fund.chain
    { hash: "0x#{'a' * 64}", to: to || chain.factory, from: address_of(:alice), input: input || Chain::Create2.calldata(fund) }
  end

  test "a made-up deploy hash does not move a fund to deploying" do
    fund = configured_draft
    sign_in_as @admin
    patch account_safe_path(fund), params: { deploy_tx_hash: "0x#{'b' * 64}" }, as: :json
    assert_response :success
    assert_equal "draft", fund.reload.safe_status
    assert_nil fund.deploy_tx_hash
    assert_equal "draft", json["status"]
  end

  test "a real hash of an unrelated transaction is refused" do
    fund = configured_draft
    hash = "0x#{'a' * 64}"
    @fake.transactions[hash] = deploy_tx(fund, to: address_of(:erin))
    sign_in_as @admin
    patch account_safe_path(fund), params: { deploy_tx_hash: hash }, as: :json
    assert_equal "deploy_tx_mismatch", json["error"]
    assert_equal "draft", fund.reload.safe_status

    @fake.transactions[hash] = deploy_tx(fund, input: "0xdeadbeef")
    patch account_safe_path(fund), params: { deploy_tx_hash: hash }, as: :json
    assert_equal "deploy_tx_mismatch", json["error"]
    assert_equal "draft", fund.reload.safe_status
  end

  test "the matching transaction moves the fund to deploying" do
    fund = configured_draft
    hash = "0x#{'a' * 64}"
    @fake.transactions[hash] = deploy_tx(fund)
    sign_in_as @admin
    patch account_safe_path(fund), params: { deploy_tx_hash: hash }, as: :json
    assert_equal "deploying", fund.reload.safe_status
    assert_equal hash, fund.deploy_tx_hash
  end

  test "the scheduler backs off a deploying fund and gives up after the attempt limit" do
    fund = configured_draft
    fund.update!(safe_status: "deploying", deploy_tx_hash: "0x#{'a' * 64}")
    assert_enqueued_with(job: SafeDeploymentVerificationJob, args: [ fund.id ]) { ChainSyncSchedulerJob.perform_now }
    SafeDeploymentVerificationJob.perform_now(fund.id)
    assert_equal 1, fund.reload.safe_verification_attempts
    assert_operator fund.safe_verification_next_at, :>, Time.current
    assert_no_enqueued_jobs(only: SafeDeploymentVerificationJob) { ChainSyncSchedulerJob.perform_now }

    previous = fund.safe_verification_next_at
    travel_to previous + 1.second do
      SafeDeploymentVerificationJob.perform_now(fund.id)
    end
    assert_operator fund.reload.safe_verification_next_at - previous, :>, 1.minute

    fund.update_columns(safe_verification_attempts: Chain::DeploymentVerifier::MAX_ATTEMPTS, safe_verification_next_at: nil)
    SafeDeploymentVerificationJob.perform_now(fund.id)
    assert_equal "draft", fund.reload.safe_status
    assert_equal "deploy_tx_not_found", fund.safe_verification_error
  end

  test "fund creation is limited per person" do
    sign_in_as @member
    created = 0
    with_counting_rate_limit_store do
      12.times do |i|
        post accounts_path, params: { account: { name: "Fonds nummer #{i}" } }
        created += 1 if response.location&.include?("uitnodigen")
      end
    end
    assert_equal AccountsController::FUNDS_PER_HOUR, created
  end

  # --- M4

  def dust_log(from, amount, block)
    { address: @fund.token_address, topics: [ Chain::LogSync::TRANSFER, "0x#{from.delete_prefix('0x').rjust(64, '0')}", "0x#{S.delete_prefix('0x').rjust(64, '0')}" ],
      data: format("0x%064x", amount), block_number: block, block_hash: FakeRpc.block_hash(block), tx_hash: format("0x%064x", block), log_index: 1, removed: false }
  end

  test "dust rows no longer drive RPC volume: 40 rows in 40 blocks cost one block request" do
    @fund.update!(synced_block: 1950)
    lookalike = address_of(:erin)
    @fake.logs = 40.times.map { |i| dust_log(lookalike, 1, 1951 + i) }
    Chain::LogSync.new(@fund).call
    assert_equal 40, @fund.chain_events.count
    @fake.logs = []
    @fake.calls.clear
    Chain::LogSync.new(@fund).call
    assert_operator @fake.calls.size, :<=, 7, @fake.calls.tally.inspect
    assert_equal 1, @fake.calls.count(:get_blocks)
  end

  test "a reorged block is still noticed through the batch" do
    @fund.update!(synced_block: 1950)
    @fake.logs = [ dust_log(address_of(:erin), 5_000_000, 1960) ]
    Chain::LogSync.new(@fund).call
    assert_equal 1, @fund.chain_events.count
    @fake.logs = []
    @fake.blocks[1960] = { number: 1960, hash: format("0x%064x", 123), timestamp: 1 }
    Chain::LogSync.new(@fund).call
    assert_equal 0, @fund.chain_events.count
  end

  test "dust from unknown senders is collapsed behind a toggle, with the data intact" do
    @fund.update!(synced_block: 1950)
    @fake.logs = [ dust_log(address_of(:erin), 1, 1960), dust_log(address_of(:erin), 5_000_000, 1961) ]
    Chain::LogSync.new(@fund).call
    sign_in_as @member
    get account_activity_path(@fund)
    assert_no_match "+0,000001 EURC", response.body
    assert_match "+5,00 EURC", response.body
    assert_select "a", text: /1 klein bedrag/
    get account_activity_path(@fund, dust: "1")
    assert_match "+0,000001 EURC", response.body

    get account_chain_events_path(@fund, format: :csv)
    assert_equal 3, response.body.lines.size, "CSV keeps everything"
    get dashboard_path
    assert_no_match "0,000001", response.body
  end

  test "dust from a member is not hidden, and an unknown sender is shown in full" do
    @fund.update!(synced_block: 1950)
    @fund.account_memberships.update_all(joined_at: 10.years.ago)
    @member.wallets.update_all(verified_at: 10.years.ago)
    @fake.logs = [ dust_log(address_of(:bob), 1, 1960), dust_log(address_of(:erin), 5_000_000, 1961) ]
    Chain::LogSync.new(@fund).call
    sign_in_as @admin
    get account_activity_path(@fund)
    assert_match "+0,000001 EURC", response.body
    assert_select "[data-testid=unknown-sender-address]", text: Chain::Address.checksum(address_of(:erin))
  end

  test "a look-alike of a member's wallet gets a warning" do
    bob = address_of(:bob)
    lookalike = "#{bob[0, 6]}#{'0' * 32}#{bob[-4..]}"
    @fund.chain_events.create!(chain_id: SEPOLIA, tx_hash: "0x#{'c' * 64}", log_index: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990),
                               kind: "token_in", from_address: lookalike, to_address: S, token_address: @fund.token_address, amount: 5_000_000, occurred_at: Time.current)
    sign_in_as @admin
    get account_activity_path(@fund)
    assert_select "[data-testid=lookalike-warning]"
  end

  # --- M10

  test "a hint for an unrelated mined transaction cannot flip a proposal, whatever the nonce did" do
    row = stored_proposal(nonce: 5)
    @fake.nonce = 6
    other = "0x#{'9' * 64}"
    @fake.receipts[other] = { tx_hash: other, status: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990), logs: [] }
    sign_in_as @member
    post account_proposal_execution_path(@fund, row), params: { tx_hash: other }, as: :json
    assert_equal "unrelated", json["execution_check"]
    assert_equal "open", row.reload.state, "only a matching execution event or a caught-up sync changes state"
  end

  test "a hint with this proposal's execution in its logs does flip it" do
    row = stored_proposal(nonce: 5)
    @fake.nonce = 6
    tx = "0x#{'8' * 64}"
    log = { address: S, topics: [ Chain::LogSync::EXECUTION_SUCCESS, row.safe_tx_hash ], data: format("0x%064x", 0), block_number: 1990,
            block_hash: FakeRpc.block_hash(1990), tx_hash: tx, log_index: 3, removed: false }
    @fake.receipts[tx] = { tx_hash: tx, status: 1, block_number: 1990, block_hash: FakeRpc.block_hash(1990), logs: [ log ] }
    sign_in_as @member
    post account_proposal_execution_path(@fund, row), params: { tx_hash: tx }, as: :json
    assert_equal "executed", json["execution_check"]
    assert_equal "executed", row.reload.state
  end

  test "a lagging node does not reopen a superseded proposal" do
    row = stored_proposal(nonce: 5, state: "superseded")
    @fund.update!(synced_block: 2500)
    @fake.nonce = 5 # The endpoint is behind: its head is 2000.
    Chain::LogSync.new(@fund).call
    assert_equal "superseded", row.reload.state
  end

  test "a lower nonce alone does not reopen a superseded proposal, a reorg does" do
    row = stored_proposal(nonce: 5, state: "superseded")
    @fund.update!(synced_block: 1990)
    @fake.nonce = 5
    Chain::LogSync.new(@fund).call
    assert_equal "superseded", row.reload.state

    @fund.update!(synced_block: 1950, synced_block_hash: format("0x%064x", 7)) # Not the hash of block 1950: a reorg.
    @fund.update!(synced_block: 1950)
    Chain::LogSync.new(@fund).call
    assert_equal "open", row.reload.state
  end

  # --- M9

  def second_fund
    @fund.account_memberships.find_by(user: @admin).update!(role: "admin")
    other = Account.create!(name: "Fonds Twee")
    add_to_fund(@admin, other, role: "admin")
    other
  end

  test "the form for fund A acts on A after fund B was viewed in another tab" do
    other = second_fund
    target_in_both = create_user("lidbeide")
    add_to_fund(target_in_both, @fund)
    add_to_fund(target_in_both, other)
    sign_in_as @admin

    get users_path(account_id: @fund.id)
    assert_select "input[name=account_id][value=?]", @fund.id.to_s
    get account_invite_path(other) # Fund B is now the last viewed.
    assert_equal other.id, @admin.reload.current_account_id

    delete user_path(target_in_both), params: { account_id: @fund.id }
    assert_not @fund.active_users.exists?(target_in_both.id)
    assert other.active_users.exists?(target_in_both.id)

    post invitations_path, params: { account_id: @fund.id, invitation: { email: "x@example.com" } }
    assert_equal 1, @fund.invitations.where(email: "x@example.com").count
    assert_equal 0, other.invitations.where(email: "x@example.com").count

    patch settings_path, params: { account_id: @fund.id, account: { name: "Fonds Een Nieuw" } }
    assert_equal "Fonds Een Nieuw", @fund.reload.name
    assert_equal "Fonds Twee", other.reload.name
  end

  test "an action that names no fund does nothing, whatever was viewed last" do
    other = second_fund
    member = add_to_fund(create_user("lid"), other)
    sign_in_as @admin
    get account_invite_path(other)
    delete user_path(member)
    assert_redirected_to dashboard_path
    assert_match "om welk fonds", flash[:alert]
    assert other.active_users.exists?(member.id)
    assert_no_difference("Invitation.count") { post invitations_path, params: { invitation: { email: "y@example.com" } } }
    patch settings_path, params: { account: { name: "Gekaapt" } }
    assert_equal "Fonds Twee", other.reload.name
  end

  test "naming a fund you are no admin of is refused" do
    other = Account.create!(name: "Ander fonds")
    add_to_fund(@member, other)
    target = add_to_fund(create_user("doelwit"), other)
    sign_in_as @member
    delete user_path(target), params: { account_id: other.id }
    assert other.active_users.exists?(target.id)
    assert_redirected_to dashboard_path
  end

  test "a prefetched page does not switch the current fund" do
    other = second_fund
    sign_in_as @admin
    @admin.update!(current_account: @fund)
    get account_contribute_path(other), headers: { "Sec-Purpose" => "prefetch" }
    assert_equal @fund.id, @admin.reload.current_account_id
    get account_contribute_path(other), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_equal @fund.id, @admin.reload.current_account_id
    get account_contribute_path(other)
    assert_equal other.id, @admin.reload.current_account_id
  end

  # --- Roles

  test "an admin sets roles, and the page offers it" do
    target = add_to_fund(create_user("rol"), @fund)
    sign_in_as @admin
    get users_path(account_id: @fund.id)
    assert_select "form[action=?]", user_path(target)
    assert_select "select[name=role]"
    patch user_path(target), params: { account_id: @fund.id, role: "viewer" }
    assert @fund.account_memberships.find_by(user: target).viewer?
    assert_match "niets op de blockchain", flash[:notice]
    patch user_path(target), params: { account_id: @fund.id, role: "admin" }
    assert @fund.account_memberships.find_by(user: target).admin?
    patch user_path(target), params: { account_id: @fund.id, role: "koning" }
    assert_match "bestaat niet", flash[:alert]
  end

  test "the last admin cannot be demoted, also not by themselves" do
    @fund.account_memberships.where.not(user: @admin).update_all(role: "member")
    sign_in_as @admin
    patch user_path(@admin), params: { account_id: @fund.id, role: "member" }
    assert_match "minstens een admin", flash[:alert]
    assert @fund.account_memberships.find_by(user: @admin).admin?
  end

  test "a member cannot set roles, and a viewer loses the right to act at once" do
    target = add_to_fund(create_user("rol"), @fund)
    sign_in_as @member
    patch user_path(target), params: { account_id: @fund.id, role: "admin" }
    assert_redirected_to dashboard_path
    assert @fund.account_memberships.find_by(user: target).member?
    sign_out
    sign_in_as @admin
    patch user_path(target), params: { account_id: @fund.id, role: "viewer" }
    sign_out
    sign_in_as target
    post account_proposals_path(@fund), params: { kind: "change_threshold", title: "x", params: { threshold: "1" } }, as: :json
    assert_response :forbidden
  end
end

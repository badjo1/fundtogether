require "test_helper"

class SafeProposalsTest < ActionDispatch::IntegrationTest
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
    @owners = [ address_of(:alice), address_of(:bob) ]
    activate_safe(@fund, owners: @owners, threshold: 2)
    @safe = @fund.safe_address
    @token = @fund.token_address
    @fake = install_fake_rpc(FakeRpc.new)
    @fake.owners = @owners.dup
    @fake.threshold = 2
    @fake.nonce = 5
    @fake.balance = 10**12
    @fake.native_balance = 10**18
    @recipient = address_of(:dave)
  end

  teardown { uninstall_fake_rpc }

  def propose(kind: "transfer_token", title: "Uitbetaling", params: { recipient: @recipient, amount: "1000000" }, **rest)
    post account_proposals_path(@fund), params: { kind: kind, title: title, params: params }.merge(rest), as: :json
  end

  def propose!(**args)
    propose(**args)
    assert_response :created, response.body
    SafeProposal.find(json["id"])
  end

  def sign(proposal, key, hash: proposal.safe_tx_hash)
    post account_proposal_signatures_path(@fund, proposal), params: { signature: sign_hash(key, hash) }, as: :json
  end

  def tamper(proposal, **fields)
    SafeProposal.where(id: proposal.id).update_all(fields)
  end

  def execution_log(proposal, topic: Chain::LogSync::EXECUTION_SUCCESS)
    { address: @safe, topics: [ topic, proposal.safe_tx_hash ], data: "0x#{'0' * 64}", block_number: 2000,
      block_hash: FakeRpc.block_hash(2000), tx_hash: "0x#{'e' * 64}", log_index: 3, removed: false }
  end

  # create

  test "a member proposes a token transfer: the server builds everything" do
    sign_in_as @member
    propose
    assert_response :created, response.body
    data = json
    assert_equal "transfer_token", data["kind"]
    assert_equal "open", data["state"]
    assert_equal @token, data["to"]
    assert_equal "0", data["value"]
    assert_equal 0, data["operation"]
    assert_equal "5", data["nonce"]
    assert_equal Chain::Abi.call(:transfer, %w[address uint256], [ @recipient, 1_000_000 ]), data["data"]
    assert_equal({ "recipient" => @recipient, "amount" => "1000000" }, data["params"])
    assert_equal SEPOLIA_ID, data["chain_id"]
    assert_equal @safe, data["safe_address"]
    assert_equal({ "address" => @token, "symbol" => "EURC", "decimals" => 6 }, data["token"])
    %w[safe_tx_gas base_gas gas_price].each { |field| assert_equal "0", data[field] }
    assert_equal Chain::Address::ZERO, data["gas_token"]
    assert_equal Chain::Address::ZERO, data["refund_receiver"]
    assert_equal({ "id" => @member.id, "name" => @member.display_name }, data["proposer"])
    assert_equal Chain::Eip712.safe_tx_hash(chain_id: SEPOLIA_ID, safe: @safe, to: @token, value: 0, data: data["data"], operation: 0, nonce: 5), data["safe_tx_hash"]
    assert_equal @member, SafeProposal.find(data["id"]).proposer
  end

  SEPOLIA_ID = ChainTestHelper::SEPOLIA

  test "stored and JSON amounts keep full uint256 precision" do
    sign_in_as @member
    max = ((2**256) - 1).to_s
    propose(kind: "transfer_native", params: { recipient: @recipient, amount: max })
    assert_equal max, json["value"]
    assert_equal max, SafeProposal.find(json["id"]).value.to_i.to_s
  end

  test "viewer cannot propose, inactive and outsiders do not see the fund" do
    { @viewer => :forbidden, @inactive => :not_found, @outsider => :not_found }.each do |user, status|
      sign_in_as user
      assert_no_difference("SafeProposal.count") { propose }
      assert_response status, user.name
    end
  end

  test "not logged in" do
    propose
    assert_response :unauthorized
    get account_proposals_path(@fund), as: :json
    assert_response :unauthorized
  end

  test "a draft fund cannot have proposals" do
    @fund.update_columns(safe_status: "deploying")
    sign_in_as @admin
    propose
    assert_response :conflict
    assert_equal "safe_not_active", json["error"]
  end

  test "clients cannot submit calldata" do
    sign_in_as @member
    propose(params: { recipient: @recipient, amount: "1", data: "0xdeadbeef" })
    assert_equal "unexpected_param", json["error"]
    propose(params: { recipient: @recipient, amount: "1", to: address_of(:erin) })
    assert_equal "unexpected_param", json["error"]
    propose(params: "0xdeadbeef")
    assert_equal "unexpected_param", json["error"]
    # Top-level fields are ignored entirely: what is stored comes from the builder.
    propose(to: address_of(:erin), data: "0xdeadbeef", operation: 1, value: "9", nonce: "1")
    assert_response :created
    assert_equal @token, json["to"]
    assert_equal 0, json["operation"]
    assert_equal "0", json["value"]
    assert_equal "5", json["nonce"]
  end

  test "unknown kinds and malformed fields" do
    sign_in_as @member
    propose(kind: "enable_module", params: { module: @recipient })
    assert_equal "unknown_kind", json["error"]
    propose(title: "")
    assert_equal "invalid_title", json["error"]
    propose(title: nil)
    assert_equal "invalid_title", json["error"]
    propose(title: "x" * 121)
    assert_equal "invalid_title", json["error"]
    propose(title: [ "x" ])
    assert_equal "invalid_title", json["error"]
    propose(params: { recipient: "0x12", amount: "1" })
    assert_equal "invalid_address", json["error"]
    propose(params: { recipient: @recipient, amount: "-1" })
    assert_equal "invalid_amount", json["error"]
    propose(params: { recipient: @safe, amount: "1" })
    assert_equal "recipient_forbidden", json["error"]
    assert_response :unprocessable_entity
    assert_equal 0, SafeProposal.count
  end

  test "an RPC failure at creation is an error and stores nothing" do
    @fake.fail_with(:eth_call)
    sign_in_as @member
    assert_no_difference("SafeProposal.count") { propose }
    assert_response :service_unavailable
    assert_equal "rpc_unavailable", json["error"]
  end

  test "empty return data from the node is an error, not zero owners" do
    @fake.fail_with(:eth_call, Chain::Rpc::InvalidResponse.new("leeg"))
    sign_in_as @member
    propose
    assert_response :service_unavailable
  end

  # nonces

  test "nonce is the higher of the chain and one above the highest open proposal" do
    sign_in_as @member
    assert_equal "5", propose!.nonce.to_i.to_s
    assert_equal 6, propose!(params: { recipient: @recipient, amount: "2" }).nonce.to_i
    @fake.nonce = 20
    assert_equal 20, propose!(params: { recipient: @recipient, amount: "3" }).nonce.to_i
  end

  test "the lowest free nonce: an owner fills what is free below the highest open proposal" do
    sign_in_as @member
    propose! # nonce 5
    @fake.nonce = 3
    assert_equal 3, propose!(params: { recipient: @recipient, amount: "2" }).nonce.to_i
    assert_equal 4, propose!(params: { recipient: @recipient, amount: "3" }).nonce.to_i
    assert_equal 6, propose!(params: { recipient: @recipient, amount: "4" }).nonce.to_i
  end

  test "rejection shares the nonce of its target, nothing else may" do
    sign_in_as @member
    target = propose!
    rejection = propose!(kind: "rejection", title: "Niet doen", params: { nonce: target.nonce.to_i.to_s })
    assert_equal target.nonce, rejection.nonce
    assert_equal @safe, rejection.to
    assert_equal "0x", rejection.data
    assert_equal 0, rejection.value.to_i

    get account_proposal_path(@fund, target), as: :json
    assert_equal [ rejection.id ], json["live"]["siblings"]
    assert_includes json["live"]["warnings"], "sibling_at_same_nonce"
  end

  test "rejection refusals" do
    sign_in_as @member
    propose(kind: "rejection", params: { nonce: "4" })
    assert_equal "nonce_too_low", json["error"]
    propose(kind: "rejection", params: { nonce: "abc" })
    assert_equal "invalid_nonce", json["error"]
    propose(kind: "rejection", params: { nonce: "5" })
    assert_equal "rejection_without_target", json["error"]

    target = propose!
    propose!(kind: "rejection", params: { nonce: target.nonce.to_i.to_s })
    propose(kind: "rejection", params: { nonce: target.nonce.to_i.to_s })
    assert_response :conflict
    assert_equal "proposal_duplicate", json["error"]
  end

  # owner management

  test "swap derives prev owner from the live list" do
    link_wallet(@member, :dave)
    sign_in_as @admin
    proposal = propose!(kind: "swap_owner", params: { old_owner: @owners[1], new_owner: address_of(:dave) })
    assert_equal Chain::Abi.call(:swap_owner, %w[address address address], [ @owners[0], @owners[1], address_of(:dave) ]), proposal.data
    assert_equal @safe, proposal.to
  end

  test "new owners must be verified wallets of active signing members" do
    sign_in_as @admin
    propose(kind: "add_owner", params: { owner: address_of(:dave), threshold: 2 })
    assert_equal "owner_not_verified", json["error"]
    link_wallet(@viewer, :erin)
    propose(kind: "add_owner", params: { owner: address_of(:erin), threshold: 2 })
    assert_equal "owner_is_viewer", json["error"]
    link_wallet(@member, :frank)
    propose(kind: "add_owner", params: { owner: address_of(:frank), threshold: 2 })
    assert_equal "owner_duplicate_member", json["error"]
    propose(kind: "swap_owner", params: { old_owner: @owners[0], new_owner: address_of(:frank) })
    assert_equal "owner_duplicate_member", json["error"]
    propose(kind: "swap_owner", params: { old_owner: @owners[1], new_owner: address_of(:frank) })
    assert_response :created
  end

  test "owner proposals respect threshold acknowledgement" do
    sign_in_as @admin
    propose(kind: "change_threshold", params: { threshold: 1 })
    assert_equal "risk_not_acknowledged", json["error"]
    # Leaves a 1-of-1, which is not a risk-rule case.
    propose(kind: "remove_owner", params: { owner: @owners[1], threshold: 1 })
    assert_response :created
  end

  test "lowering the threshold warns" do
    sign_in_as @admin
    proposal = propose!(kind: "change_threshold", params: { threshold: 1 }, acknowledge_risk: true)
    get account_proposal_path(@fund, proposal), as: :json
    assert_includes json["live"]["warnings"], "lowers_threshold"
  end

  # Was "only one open owner change": a member could use that to block every owner change (SECURITY_REVIEW H1).
  # At one nonce they exclude each other on-chain, so one executing cannot leave the other with stale calldata.
  test "open owner changes share the live nonce and warn about each other" do
    wallet_owner = add_to_fund(create_user("nieuw"), @fund)
    link_wallet(wallet_owner, :frank)
    sign_in_as @admin
    first = propose!(kind: "change_threshold", params: { threshold: 1 }, acknowledge_risk: true)
    second = propose!(kind: "swap_owner", params: { old_owner: @owners[1], new_owner: address_of(:frank) })
    assert_equal first.nonce, second.nonce
    assert_includes json["live"]["warnings"], "sibling_at_same_nonce"
    assert_equal [ first.id ], json["live"]["siblings"]
  end

  # reading and computed state

  test "viewers can read proposals; outsiders cannot; another fund's id is not found" do
    proposal = Chain::ProposalCreator.new(account: @fund, proposer: @member)
                                     .call(kind: "transfer_token", title: "x", params: { "recipient" => @recipient, "amount" => "1" })
    sign_in_as @viewer
    get account_proposal_path(@fund, proposal), as: :json
    assert_response :ok
    get account_proposals_path(@fund), as: :json
    assert_equal [ proposal.id ], json["proposals"].map { |row| row["id"] }

    [ @outsider, @inactive ].each do |user|
      sign_in_as user
      get account_proposal_path(@fund, proposal), as: :json
      assert_response :not_found
    end

    add_to_fund(@outsider, accounts(:two))
    sign_in_as @outsider
    get account_proposal_path(accounts(:two), proposal), as: :json
    assert_response :not_found
  end

  test "live state during an outage is labelled, the stored proposal stays readable" do
    sign_in_as @member
    proposal = propose!
    @fake.fail_with(:eth_call)
    get account_proposal_path(@fund, proposal), as: :json
    assert_response :ok
    assert_equal proposal.safe_tx_hash, json["safe_tx_hash"]
    assert_equal false, json["live"]["available"]
    assert_equal "rpc_unavailable", json["live"]["error"]
    assert_not json["live"].key?("executable")
  end

  test "executable is computed live: threshold reached, then a threshold change" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :alice)
    assert_response :created, response.body
    assert_equal false, json["live"]["executable"]
    assert_equal "not_enough_signatures", json["live"]["reason"]
    assert_equal [ address_of(:alice) ], json["signatures"].map { |row| row["signer"] }
    assert_equal 1, json["live"]["missing_signatures"]

    # Threshold lowered on-chain: the older partial set is now enough, without any write here.
    @fake.threshold = 1
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal true, json["live"]["executable"]
    assert_nil json["live"]["reason"]
    assert_not SafeProposal.column_names.include?("executable")

    # Threshold raised again: not executable.
    @fake.threshold = 3
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal false, json["live"]["executable"]
  end

  test "signature count ignores a signer who stopped being an owner" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :alice)
    sign_in_as @member
    sign(proposal, :bob)
    assert_equal true, json["live"]["executable"]
    assert_equal @owners, json["live"]["valid_signers"]

    @fake.owners = [ address_of(:bob), address_of(:carol) ]
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal false, json["live"]["executable"]
    assert_equal [ address_of(:bob) ], json["live"]["valid_signers"]
    assert_equal [ address_of(:alice) ], json["live"]["stale_signers"]

    # Signer re-added: the old signature counts again, as on-chain.
    @fake.owners = @owners.dup
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal true, json["live"]["executable"]
  end

  test "a later nonce waits, a passed nonce cannot execute" do
    sign_in_as @admin
    first = propose!
    second = propose!(params: { recipient: @recipient, amount: "2" })
    get account_proposal_path(@fund, second), as: :json
    assert_equal "waiting_for_earlier_nonce", json["live"]["reason"]
    @fake.nonce = 6
    get account_proposal_path(@fund, first), as: :json
    assert_equal "nonce_passed", json["live"]["reason"]
  end

  test "an owner proposal goes stale when the owner list moved, even with enough signatures" do
    link_wallet(@member, :frank)
    sign_in_as @admin
    proposal = propose!(kind: "swap_owner", params: { old_owner: @owners[1], new_owner: address_of(:frank) })
    sign(proposal, :alice)
    sign_in_as @member
    sign(proposal, :bob)
    assert_equal true, json["live"]["executable"]

    # Someone inserted between: prev_owner in the signed calldata is now wrong.
    @fake.owners = [ @owners[0], address_of(:carol), @owners[1] ]
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal false, json["live"]["executable"]
    assert_equal "calldata_stale", json["live"]["reason"]
  end

  test "tampering shows in the computed state" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :alice)
    tamper(proposal, to: address_of(:erin))
    get account_proposal_path(@fund, proposal), as: :json
    assert_equal false, json["live"]["executable"]
    assert_equal "tampered", json["live"]["reason"]
    assert_empty json["live"]["valid_signers"]
  end

  # signatures

  test "the signer must be this user's verified wallet" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :bob)
    assert_response :forbidden
    assert_equal "signer_not_your_wallet", json["error"]
    assert_empty proposal.safe_signatures

    sign(proposal, :frank)
    assert_equal "signer_not_your_wallet", json["error"]
  end

  test "a revoked wallet cannot sign" do
    sign_in_as @admin
    proposal = propose!
    Wallet.find_by!(address: address_of(:alice)).revoke!
    sign(proposal, :alice)
    assert_equal "signer_not_your_wallet", json["error"]
  end

  test "a verified wallet that is not an owner cannot sign" do
    link_wallet(@admin, :frank)
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :frank)
    assert_response :forbidden
    assert_equal "signer_not_owner", json["error"]
  end

  test "a stale owner cannot sign after an owner change" do
    sign_in_as @admin
    proposal = propose!
    @fake.owners = [ address_of(:bob), address_of(:carol) ]
    sign(proposal, :alice)
    assert_response :forbidden
    assert_equal "signer_not_owner", json["error"]
  end

  test "a signature for another proposal is refused" do
    sign_in_as @admin
    proposal = propose!
    other = propose!(params: { recipient: @recipient, amount: "2" })
    sign(proposal, :alice, hash: other.safe_tx_hash)
    assert_response :forbidden
    assert_equal "signer_not_your_wallet", json["error"]
    assert_empty proposal.safe_signatures
  end

  test "a signature for the same call on another Safe or chain is refused" do
    sign_in_as @admin
    proposal = propose!
    fields = { to: proposal.to, value: 0, data: proposal.data, operation: 0, nonce: 5 }
    sign(proposal, :alice, hash: Chain::Eip712.safe_tx_hash(chain_id: 100, safe: @safe, **fields))
    assert_equal "signer_not_your_wallet", json["error"]
    sign(proposal, :alice, hash: Chain::Eip712.safe_tx_hash(chain_id: SEPOLIA_ID, safe: address_of(:erin), **fields))
    assert_equal "signer_not_your_wallet", json["error"]
  end

  test "tampered stored fields block signing, whichever field" do
    sign_in_as @admin
    { to: address_of(:erin), value: 1, data: "0x", nonce: 6, safe_tx_hash: "0x#{'a' * 64}" }.each do |field, value|
      proposal = propose!(params: { recipient: @recipient, amount: (field.hash.abs % 1000 + 1).to_s })
      original = proposal.public_send(field)
      tamper(proposal, field => value)
      sign(proposal, :alice)
      assert_response :conflict, field.to_s
      assert_equal "proposal_tampered", json["error"], field.to_s
      tamper(proposal, field => original)
      SafeProposal.where(id: proposal.id).delete_all
    end
  end

  test "malformed signatures" do
    sign_in_as @admin
    proposal = propose!
    good = sign_hash(:alice, proposal.safe_tx_hash)
    [ "0x", "0xzz", good[0, 130], "#{good}00", nil, 7, [ good ], { a: 1 }, high_s_copy(good), "#{good[0, 130]}1d", "#{good[0, 130]}1f" ].each do |bad|
      post account_proposal_signatures_path(@fund, proposal), params: { signature: bad }, as: :json
      assert_response :unprocessable_entity, bad.inspect
      assert_equal "invalid_signature", json["error"], bad.inspect
    end
    assert_empty proposal.safe_signatures
  end

  test "v 0/1 is stored as canonical 27/28, uppercase as lowercase" do
    sign_in_as @admin
    proposal = propose!
    good = sign_hash(:alice, proposal.safe_tx_hash)
    post account_proposal_signatures_path(@fund, proposal), params: { signature: "#{good[0, 130]}#{format('%02x', good[130, 2].to_i(16) - 27)}" }, as: :json
    assert_response :created
    assert_equal good, proposal.safe_signatures.first.signature
  end

  test "replaying a signature is idempotent, there is no second row" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :alice)
    sign(proposal, :alice)
    assert_response :created
    assert_equal 1, proposal.safe_signatures.count
  end

  test "another encoding from the same signer is refused" do
    sign_in_as @admin
    proposal = propose!
    proposal.safe_signatures.create!(signer_address: address_of(:alice), signature: "0x#{'a' * 128}1b", user: @admin)
    sign(proposal, :alice)
    assert_response :conflict
    assert_equal "already_signed", json["error"]
  end

  test "signature recorded against the user, role checks by role" do
    sign_in_as @admin
    proposal = propose!
    sign(proposal, :alice)
    assert_equal @admin, proposal.safe_signatures.first.user

    link_wallet(@viewer, :carol)
    @fake.owners << address_of(:carol)
    sign_in_as @viewer
    sign(proposal, :carol)
    assert_response :forbidden
    assert_equal "forbidden", json["error"]

    [ @inactive, @outsider ].each do |user|
      sign_in_as user
      sign(proposal, :carol)
      assert_response :not_found
    end
  end

  test "signing is refused on a proposal that is not open, or whose nonce passed" do
    sign_in_as @admin
    proposal = propose!
    @fake.nonce = 6
    sign(proposal, :alice)
    assert_response :conflict
    assert_equal "proposal_stale", json["error"]

    SafeProposal.where(id: proposal.id).update_all(state: "executed")
    sign(proposal, :alice)
    assert_equal "proposal_not_open", json["error"]
  end

  test "an RPC failure on signing stores nothing" do
    sign_in_as @admin
    proposal = propose!
    @fake.fail_with(:eth_call)
    sign(proposal, :alice)
    assert_response :service_unavailable
    assert_empty proposal.safe_signatures
  end

  test "writes are rate limited" do
    sign_in_as @member
    with_counting_rate_limit_store do
      21.times { propose(params: { recipient: "0x12", amount: "1" }) }
    end
    assert_response :too_many_requests
  end

  # execution: state comes from chain events, never from the claim

  def receipt_with(*logs, status: 1, tx_hash: "0x#{'e' * 64}")
    @fake.receipts[tx_hash] = { tx_hash: tx_hash, status: status, block_number: 2000, block_hash: FakeRpc.block_hash(2000), logs: logs }
  end

  def report_execution(proposal, tx_hash: "0x#{'e' * 64}")
    post account_proposal_execution_path(@fund, proposal), params: { tx_hash: tx_hash }, as: :json
  end

  test "ExecutionSuccess in the receipt marks it executed and supersedes siblings" do
    sign_in_as @admin
    proposal = propose!
    sibling = propose!(kind: "rejection", params: { nonce: "5" })
    receipt_with(execution_log(proposal))
    @fake.nonce = 6

    report_execution(proposal)
    assert_response :ok, response.body
    assert_equal "executed", json["execution_check"]
    assert_equal "executed", json["state"]
    assert_equal "0x#{'e' * 64}", json["execution_tx_hash"]
    assert_predicate json["executed_at"], :present?
    assert_equal "superseded", sibling.reload.state

    event = @fund.chain_events.find_by!(kind: "execution_success")
    assert_equal proposal, event.safe_proposal
    assert_not event.finalized
  end

  test "ExecutionFailure with status 1 means failed: nonce burned, nothing moved" do
    sign_in_as @admin
    proposal = propose!
    receipt_with(execution_log(proposal, topic: Chain::LogSync::EXECUTION_FAILURE))
    @fake.nonce = 6
    report_execution(proposal)
    assert_equal "failed", json["execution_check"]
    assert_equal "failed", json["state"]
  end

  test "status 0 means nothing happened" do
    sign_in_as @admin
    proposal = propose!
    receipt_with(status: 0)
    report_execution(proposal)
    assert_equal "reverted", json["execution_check"]
    assert_equal "open", json["state"]
  end

  test "an unmined transaction is pending and enqueues a sync" do
    sign_in_as @admin
    proposal = propose!
    assert_enqueued_with(job: ChainSyncJob, args: [ @fund.id ]) { report_execution(proposal) }
    assert_response :accepted
    assert_equal "pending", json["execution_check"]
    assert_equal "open", json["state"]
    assert_nil json["execution_tx_hash"]
  end

  test "a claimed hash that executed something else changes nothing" do
    sign_in_as @admin
    proposal = propose!
    other = propose!(params: { recipient: @recipient, amount: "2" })
    receipt_with(execution_log(other))
    report_execution(proposal)
    assert_equal "unrelated", json["execution_check"]
    assert_equal "open", json["state"]
    assert_equal "executed", other.reload.state
  end

  test "logs from another address in the receipt cannot execute a proposal" do
    sign_in_as @admin
    proposal = propose!
    receipt_with(execution_log(proposal).merge(address: address_of(:erin)))
    report_execution(proposal)
    assert_equal "unrelated", json["execution_check"]
    assert_equal "open", proposal.reload.state
    assert_empty @fund.chain_events
  end

  test "execution input and roles" do
    sign_in_as @admin
    proposal = propose!
    [ "0x12", "", nil, 7, [ "x" ] ].each do |bad|
      post account_proposal_execution_path(@fund, proposal), params: { tx_hash: bad }, as: :json
      assert_response :unprocessable_entity, bad.inspect
      assert_equal "invalid_tx_hash", json["error"]
    end
    { @viewer => :forbidden, @inactive => :not_found, @outsider => :not_found }.each do |user, status|
      sign_in_as user
      report_execution(proposal)
      assert_response status, user.name
    end
  end

  test "an RPC failure when reporting execution is an error" do
    sign_in_as @admin
    proposal = propose!
    @fake.fail_with(:get_receipt)
    report_execution(proposal)
    assert_response :service_unavailable
    assert_equal "open", proposal.reload.state
  end
end

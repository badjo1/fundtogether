require "test_helper"

class ChainLogSyncTest < ActiveSupport::TestCase
  setup do
    @fund = accounts(:one)
    @member = users(:two)
    AccountMembership.update_all(joined_at: Time.zone.parse("2020-01-01")) # Events in these tests are from 2023.
    @fake = install_fake_rpc(FakeRpc.new)
    @owners = [ address_of(:alice), address_of(:bob) ]
    activate_safe(@fund, owners: @owners, threshold: 2, synced_block: 1000)
    @safe = @fund.safe_address
    @token = @fund.token_address
    @fake.owners = @owners
    @fake.threshold = 2
    @fake.head = 1100
    @fake.finalized = 1050
    @log_index = 0
  end

  teardown { uninstall_fake_rpc }

  def sync
    Chain::LogSync.new(@fund).call
  end

  def topic(address)
    "0x#{word(address)}"
  end

  def uint(number)
    "0x#{number.to_s(16).rjust(64, '0')}"
  end

  def log(address:, topics:, data: "0x", block: 1060, tx: nil, block_hash: nil)
    @log_index += 1
    { address: address, topics: topics, data: data, block_number: block, block_hash: block_hash || FakeRpc.block_hash(block),
      tx_hash: tx || format("0x%064x", @log_index + 0xfeed), log_index: @log_index, removed: false }
  end

  def transfer(from:, to:, amount: 500, **rest)
    log(address: @token, topics: [ Chain::LogSync::TRANSFER, topic(from), topic(to) ], data: uint(amount), **rest)
  end

  def safe_received(from:, amount: 7, **rest)
    log(address: @safe, topics: [ Chain::LogSync::SAFE_RECEIVED, topic(from) ], data: uint(amount), **rest)
  end

  def event(kind)
    @fund.chain_events.find_by!(kind: kind)
  end

  test "records token transfers in and out, native receipts and Safe events" do
    @fake.logs = [
      transfer(from: address_of(:dave), to: @safe),
      transfer(from: @safe, to: address_of(:erin), amount: 100, block: 1061),
      safe_received(from: address_of(:dave)),
      log(address: @safe, topics: [ Chain::LogSync::EXECUTION_SUCCESS, "0x#{'a' * 64}" ], data: uint(0)),
      log(address: @safe, topics: [ Chain::LogSync::EXECUTION_FAILURE, "0x#{'b' * 64}" ], data: uint(0)),
      log(address: @safe, topics: [ Chain::LogSync::ADDED_OWNER, topic(address_of(:carol)) ]),
      log(address: @safe, topics: [ Chain::LogSync::REMOVED_OWNER, topic(address_of(:bob)) ]),
      log(address: @safe, topics: [ Chain::LogSync::CHANGED_THRESHOLD ], data: uint(3))
    ]
    result = sync

    assert_equal 8, result.new_events
    assert result.caught_up
    assert_equal 1100, @fund.reload.synced_block
    assert_equal FakeRpc.block_hash(1100), @fund.synced_block_hash
    assert_predicate @fund.synced_at, :present?

    token_in = event("token_in")
    assert_equal address_of(:dave), token_in.from_address
    assert_equal @safe, token_in.to_address
    assert_equal @token, token_in.token_address
    assert_equal 500, token_in.amount.to_i
    assert_equal ChainTestHelper::SEPOLIA, token_in.chain_id
    assert_equal Time.zone.at(1_700_000_000 + 1060), token_in.occurred_at
    assert_equal 100, event("token_out").amount.to_i
    assert_equal 7, event("native_in").amount.to_i
    assert_nil event("native_in").token_address
    assert_equal "0x#{'a' * 64}", event("execution_success").safe_tx_hash
    assert_equal "0x#{'b' * 64}", event("execution_failure").safe_tx_hash
    assert_equal address_of(:carol), event("owner_added").to_address
    assert_equal address_of(:bob), event("owner_removed").from_address
    assert_equal 3, event("threshold_changed").amount.to_i
  end

  test "syncing twice stores nothing twice" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe) ]
    sync
    @fund.update_columns(synced_block: 1000, synced_block_hash: nil)
    assert_equal 0, sync.new_events
    assert_equal 1, @fund.chain_events.count
  end

  test "several logs in one transaction are all recorded" do
    tx = "0x#{'9' * 64}"
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, tx: tx), transfer(from: address_of(:erin), to: @safe, tx: tx, amount: 9) ]
    sync
    assert_equal 2, @fund.chain_events.where(tx_hash: tx).count
  end

  test "a transfer between two funds belongs to both" do
    other = accounts(:two)
    activate_safe(other, owners: @owners, threshold: 2, safe: "0x2222222222222222222222222222222222222222", synced_block: 1000)
    tx = "0x#{'8' * 64}"
    @fake.logs = [ transfer(from: @safe, to: other.safe_address, tx: tx) ]
    sync
    Chain::LogSync.new(other).call
    assert_equal "token_out", @fund.chain_events.find_by!(tx_hash: tx).kind
    assert_equal "token_in", other.chain_events.find_by!(tx_hash: tx).kind
  end

  test "another token and EURe V1-style mirrors are not indexed" do
    @fake.logs = [ log(address: "0xcb444e90d8198415266c6a2724b7900fb12fc56e", topics: [ Chain::LogSync::TRANSFER, topic(address_of(:dave)), topic(@safe) ], data: uint(5)) ]
    sync
    assert_empty @fund.chain_events
  end

  test "an RPC returning logs that do not match the filter is refused and the cursor stays" do
    wrong = log(address: @token, topics: [ Chain::LogSync::TRANSFER, topic(address_of(:dave)), topic(address_of(:erin)) ], data: uint(5))
    @fake.define_singleton_method(:get_logs) { |**| [ wrong ] }
    assert_raises(Chain::Rpc::InvalidResponse) { sync }
    assert_empty @fund.chain_events
    assert_equal 1000, @fund.reload.synced_block
  end

  test "logs outside the requested range are refused" do
    wrong = transfer(from: address_of(:dave), to: @safe, block: 5)
    @fake.define_singleton_method(:get_logs) { |**| [ wrong ] }
    assert_raises(Chain::Rpc::InvalidResponse) { sync }
    assert_equal 1000, @fund.reload.synced_block
  end

  test "zero-value transfers (address poisoning) and self-transfers are ignored" do
    @fake.logs = [
      transfer(from: address_of(:alice), to: @safe, amount: 0),
      transfer(from: @safe, to: address_of(:erin), amount: 0),
      transfer(from: @safe, to: @safe, amount: 5)
    ]
    sync
    assert_empty @fund.chain_events
  end

  test "a rejection's SafeReceived(safe, 0) is not a contribution" do
    @fake.logs = [ safe_received(from: @safe, amount: 0), safe_received(from: @safe, amount: 3), safe_received(from: address_of(:dave), amount: 0) ]
    sync
    assert_empty @fund.chain_events
  end

  test "malformed log data raises and keeps the cursor" do
    @fake.logs = [ log(address: @token, topics: [ Chain::LogSync::TRANSFER, topic(address_of(:dave)), topic(@safe) ], data: "0x") ]
    assert_raises(Chain::Rpc::InvalidResponse) { sync }
    assert_equal 1000, @fund.reload.synced_block
  end

  # attribution

  test "an inactive member and someone who joined after the event are not attributed" do
    wallet = link_wallet(@member, :dave)
    wallet.update!(verified_at: Time.zone.at(1_700_000_000))
    @fund.account_memberships.find_by(user: @member).update!(joined_at: Time.zone.parse("2026-01-01"))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe) ]
    sync
    assert_nil event("token_in").user

    @fund.chain_events.destroy_all
    @fund.update!(synced_block: 1000)
    @fund.account_memberships.find_by(user: @member).update!(joined_at: Time.zone.parse("2020-01-01"), active: false)
    sync
    assert_nil event("token_in").user
  end

  test "contributions are attributed by the wallet verified at event time, for members only" do
    wallet = link_wallet(@member, :dave)
    wallet.update!(verified_at: Time.zone.at(1_700_000_000 + 1000))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe) ]
    sync
    assert_equal @member, event("token_in").user
  end

  test "a wallet linked after the event does not claim it" do
    link_wallet(@member, :dave).update!(verified_at: Time.zone.at(1_700_000_000 + 1061))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    assert_nil event("token_in").user
  end

  test "a wallet revoked before the event does not claim it" do
    link_wallet(@member, :dave).update!(verified_at: Time.zone.at(1_700_000_000), revoked_at: Time.zone.at(1_700_000_000 + 1059))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    assert_nil event("token_in").user
  end

  test "an address re-linked later keeps the earlier owner's history" do
    link_wallet(users(:one), :dave).update!(verified_at: Time.zone.at(1_700_000_000), revoked_at: Time.zone.at(1_700_000_000 + 1070))
    link_wallet(@member, :dave).update!(verified_at: Time.zone.at(1_700_000_000 + 1071))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060), transfer(from: address_of(:dave), to: @safe, block: 1080) ]
    sync
    assert_equal [ users(:one), @member ], @fund.chain_events.order(:block_number).map(&:user)
  end

  test "a non-member's verified wallet stays an unknown sender" do
    outsider = User.create!(name: "Buiten", email_address: "buiten@example.com", password: "password")
    link_wallet(outsider, :dave).update!(verified_at: Time.zone.at(1_700_000_000))
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe) ]
    sync
    assert_nil event("token_in").user
  end

  test "an unknown sender is recorded as unknown" do
    @fake.logs = [ safe_received(from: address_of(:erin)) ]
    sync
    assert_nil event("native_in").user
    assert_equal address_of(:erin), event("native_in").from_address
  end

  # chunks and limits

  test "ranges are at most 2000 blocks and the cursor advances per chunk" do
    @fake.head = 5500
    @fake.finalized = 5000
    ranges = []
    original = @fake.method(:get_logs)
    @fake.define_singleton_method(:get_logs) do |**args|
      ranges << [ args[:from_block], args[:to_block] ]
      original.call(**args)
    end
    sync
    assert_equal [ [ 1001, 3000 ], [ 3001, 5000 ], [ 5001, 5500 ] ], ranges.uniq
    assert_equal 5500, @fund.reload.synced_block
  end

  test "range errors halve the range" do
    @fake.head = 1300
    @fake.log_limit = 300
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1200) ]
    sync
    assert_equal 1300, @fund.reload.synced_block
    assert_equal 1, @fund.chain_events.count
  end

  test "a range error even for one block raises" do
    @fake.log_limit = 0
    assert_raises(Chain::Rpc::RangeTooLarge) { sync }
    assert_equal 1000, @fund.reload.synced_block
  end

  test "a long gap is worked off over several runs and is not caught up until then" do
    @fake.head = 1000 + (Chain::LogSync::MAX_RANGE * Chain::LogSync::MAX_CHUNKS_PER_RUN) + 5
    @fake.finalized = @fake.head - 10
    result = sync
    assert_not result.caught_up
    assert_equal 1000 + (Chain::LogSync::MAX_RANGE * Chain::LogSync::MAX_CHUNKS_PER_RUN), @fund.reload.synced_block
    assert sync.caught_up
  end

  # failure

  test "an RPC failure while scanning keeps the cursor and propagates" do
    @fake.fail_with(:get_logs)
    assert_raises(Chain::Rpc::Unavailable) { sync }
    assert_equal 1000, @fund.reload.synced_block
    assert_nil @fund.synced_at
  end

  test "a failure in a later chunk keeps earlier chunks" do
    @fake.head = 3500
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1500) ]
    calls = 0
    original = @fake.method(:get_logs)
    @fake.define_singleton_method(:get_logs) do |**args|
      calls += 1
      raise Chain::Rpc::Unavailable, "weg" if calls > 3

      original.call(**args)
    end
    assert_raises(Chain::Rpc::Unavailable) { sync }
    assert_equal 3000, @fund.reload.synced_block
    assert_equal 1, @fund.chain_events.count
  end

  test "failure of the finalized tag falls back to confirmations" do
    @fake.head = 2000
    @fake.finalized = nil
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1050), transfer(from: address_of(:erin), to: @safe, block: 1990) ]
    sync
    # 2000 - 96 confirmations
    assert_equal [ 1050 ], @fund.chain_events.where(finalized: true).pluck(:block_number)
    assert_equal [ 1990 ], @fund.chain_events.where(finalized: false).pluck(:block_number)
  end

  # finality and reorgs

  test "events are unfinalized until the finalized block passes them" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    assert_not event("token_in").finalized
    assert_equal "in behandeling", event("token_in").status_label

    @fake.finalized = 1070
    sync
    assert event("token_in").finalized
    assert_equal "definitief", event("token_in").status_label
  end

  test "a reorg removes the row and rewinds, and the new position is found" do
    transfer_log = transfer(from: address_of(:dave), to: @safe, block: 1060)
    @fake.logs = [ transfer_log ]
    sync
    assert_equal 1, @fund.chain_events.count

    # Block 1060 was replaced, and the transaction landed in 1061.
    new_hash = "0x#{'7' * 64}"
    @fake.blocks[1060] = { number: 1060, hash: new_hash, timestamp: 1_700_001_060 }
    @fake.blocks[1100] = { number: 1100, hash: "0x#{'6' * 64}", timestamp: 1_700_001_100 }
    @fake.logs = [ transfer_log.merge(block_number: 1061, block_hash: FakeRpc.block_hash(1061)) ]
    sync

    row = @fund.chain_events.sole
    assert_equal 1061, row.block_number
    assert_equal FakeRpc.block_hash(1061), row.block_hash
  end

  test "a reorg where the transaction disappeared removes the event" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    @fake.blocks[1060] = { number: 1060, hash: "0x#{'7' * 64}", timestamp: 1_700_001_060 }
    @fake.logs = []
    sync
    assert_empty @fund.chain_events
  end

  test "a reorg at the cursor block alone rewinds to finalized" do
    sync
    assert_equal FakeRpc.block_hash(1100), @fund.reload.synced_block_hash
    @fake.head = 1100
    @fake.blocks[1100] = { number: 1100, hash: "0x#{'6' * 64}", timestamp: 1_700_001_100 }
    @fake.logs = [ transfer(from: address_of(:erin), to: @safe, block: 1080) ]
    sync
    assert_equal 1, @fund.chain_events.count, "the log added by the reorg below the old cursor was missed"
  end

  test "finalized rows are never removed" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1040) ]
    sync
    assert event("token_in").finalized
    @fake.blocks[1040] = { number: 1040, hash: "0x#{'7' * 64}", timestamp: 1 }
    sync
    assert_equal 1, @fund.chain_events.count
  end

  test "a missing block while checking raises rather than deleting" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    @fake.blocks[1060] = nil
    original = @fake.method(:get_block)
    @fake.define_singleton_method(:get_block) { |tag| tag == 1060 ? nil : original.call(tag) }
    assert_raises(Chain::Rpc::InvalidResponse) { sync }
    assert_equal 1, @fund.chain_events.count
  end

  test "an RPC failure while checking does not delete" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe, block: 1060) ]
    sync
    @fake.define_singleton_method(:get_block) { |tag| raise Chain::Rpc::Unavailable, "weg" unless tag == "finalized" }
    assert_raises(Chain::Rpc::Unavailable) { sync }
    assert_equal 1, @fund.chain_events.count
  end

  # proposal reconciliation

  def open_proposal(nonce: 5, title: "x")
    to = @fund.safe_address
    hash = Chain::Eip712.safe_tx_hash(chain_id: @fund.chain_id, safe: @safe, to: to, value: 0, data: "0x", operation: 0, nonce: nonce)
    @fund.safe_proposals.create!(proposer: @member, kind: "rejection", title: title, params: { nonce: nonce.to_s }, to: to, data: "0x", nonce: nonce, safe_tx_hash: hash)
  end

  def execution(proposal, topic: Chain::LogSync::EXECUTION_SUCCESS, block: 1060)
    log(address: @safe, topics: [ topic, proposal.safe_tx_hash ], data: uint(0), block: block)
  end

  test "execution found by sync, even if it happened outside the app" do
    proposal = open_proposal
    @fake.nonce = 6
    @fake.logs = [ execution(proposal) ]
    sync
    proposal.reload
    assert_equal "executed", proposal.state
    assert_equal event("execution_success").tx_hash, proposal.execution_tx_hash
    assert_equal proposal, event("execution_success").safe_proposal
  end

  test "an execution of an unknown hash is recorded and links nothing" do
    @fake.nonce = 6
    @fake.logs = [ log(address: @safe, topics: [ Chain::LogSync::EXECUTION_SUCCESS, "0x#{'c' * 64}" ], data: uint(0)) ]
    sync
    assert_nil event("execution_success").safe_proposal
  end

  test "another execution at the same nonce supersedes" do
    proposal = open_proposal
    @fake.nonce = 6
    @fake.logs = [ log(address: @safe, topics: [ Chain::LogSync::EXECUTION_SUCCESS, "0x#{'c' * 64}" ], data: uint(0)) ]
    sync
    assert_equal "superseded", proposal.reload.state
  end

  test "superseded waits until the scan caught up" do
    proposal = open_proposal
    @fake.nonce = 6
    @fake.head = 1000 + (Chain::LogSync::MAX_RANGE * Chain::LogSync::MAX_CHUNKS_PER_RUN) + 5
    sync
    assert_equal "open", proposal.reload.state
    sync
    assert_equal "superseded", proposal.reload.state
  end

  test "a later event overrides superseded" do
    proposal = open_proposal
    @fake.nonce = 6
    sync
    assert_equal "superseded", proposal.reload.state
    @fake.head = 1200
    @fake.logs = [ execution(proposal, block: 1150) ]
    sync
    assert_equal "executed", proposal.reload.state
  end

  test "a reorg removing the execution reopens the proposal" do
    proposal = open_proposal
    @fake.nonce = 6
    @fake.logs = [ execution(proposal) ]
    sync
    assert_equal "executed", proposal.reload.state

    @fake.nonce = 5
    @fake.logs = []
    @fake.blocks[1060] = { number: 1060, hash: "0x#{'7' * 64}", timestamp: 1 }
    sync
    proposal.reload
    assert_equal "open", proposal.state
    assert_nil proposal.execution_tx_hash
    assert_nil proposal.executed_at
  end

  test "failed execution marks failed" do
    proposal = open_proposal
    @fake.nonce = 6
    @fake.logs = [ execution(proposal, topic: Chain::LogSync::EXECUTION_FAILURE) ]
    sync
    assert_equal "failed", proposal.reload.state
  end

  test "a client hash only reads logs that belong to this fund" do
    tx = "0x#{'d' * 64}"
    @fake.receipts[tx] = { tx_hash: tx, status: 1, block_number: 1060, block_hash: FakeRpc.block_hash(1060), logs: [
      log(address: address_of(:erin), topics: [ Chain::LogSync::SAFE_RECEIVED, topic(address_of(:dave)) ], data: uint(1_000_000)),
      log(address: @token, topics: [ Chain::LogSync::TRANSFER, topic(address_of(:dave)), topic(address_of(:erin)) ], data: uint(1_000_000)),
      transfer(from: address_of(:dave), to: @safe, amount: 42, tx: tx)
    ] }
    Chain::LogSync.new(@fund).ingest_receipt(tx)
    assert_equal 42, @fund.chain_events.sole.amount.to_i
  end

  test "an unknown client hash credits nothing" do
    assert_nil Chain::LogSync.new(@fund).ingest_receipt("0x#{'d' * 64}")
    assert_empty @fund.chain_events
  end

  # jobs

  test "the sync job runs for active funds, ignores others, and passes the hint" do
    @fake.logs = [ transfer(from: address_of(:dave), to: @safe) ]
    tx = "0x#{'d' * 64}"
    ChainSyncJob.perform_now(@fund.id, tx_hash: tx)
    assert_equal 1, @fund.chain_events.count
    assert_includes @fake.receipt_requests, tx

    ChainSyncJob.perform_now(accounts(:two).id)
    ChainSyncJob.perform_now(0)
  end
end

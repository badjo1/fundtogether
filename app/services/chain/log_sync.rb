module Chain
  # Mirrors a fund's chain activity into chain_events. The cursor (synced_block) only moves after a
  # chunk is stored. Unfinalized rows and the cursor block are re-checked by hash on every run; on a
  # mismatch rows are removed and the cursor rewinds. RPC errors propagate, with nothing half-done.
  class LogSync
    MAX_RANGE = 2_000
    MAX_CHUNKS_PER_RUN = 50

    TRANSFER = Hex.from_bin(Hex.keccak("Transfer(address,address,uint256)")).freeze
    SAFE_RECEIVED = Hex.from_bin(Hex.keccak("SafeReceived(address,uint256)")).freeze
    EXECUTION_SUCCESS = Hex.from_bin(Hex.keccak("ExecutionSuccess(bytes32,uint256)")).freeze
    EXECUTION_FAILURE = Hex.from_bin(Hex.keccak("ExecutionFailure(bytes32,uint256)")).freeze
    ADDED_OWNER = Hex.from_bin(Hex.keccak("AddedOwner(address)")).freeze
    REMOVED_OWNER = Hex.from_bin(Hex.keccak("RemovedOwner(address)")).freeze
    CHANGED_THRESHOLD = Hex.from_bin(Hex.keccak("ChangedThreshold(uint256)")).freeze
    SAFE_TOPICS = [ SAFE_RECEIVED, EXECUTION_SUCCESS, EXECUTION_FAILURE, ADDED_OWNER, REMOVED_OWNER, CHANGED_THRESHOLD ].freeze

    Result = Data.define(:synced_block, :caught_up, :new_events)

    def initialize(account, rpc: nil)
      @account = account
      @chain = account.chain
      @rpc = rpc || Rpc.for(@chain)
      @safe = account.safe_address
      @token = account.token_address
      @timestamps = {}
    end

    def call
      return unless @account.safe_active?

      # Read before scanning, so every execution that moved this nonce is below the scanned head.
      chain_nonce = SafeReader.new(chain: @chain, safe: @safe, rpc: @rpc).nonce
      head = @rpc.block_number
      finalized = finalized_block(head)

      # Behind what this fund has already seen: its nonce may be old too, so it must not reopen anything.
      lagging = @account.synced_block && head < @account.synced_block

      check_stored_rows(head)
      check_cursor(finalized, head)
      new_events, caught_up = scan(head)
      @account.chain_events.unfinalized.where(block_number: ..finalized).update_all(finalized: true, updated_at: Time.current)
      ProposalReconciler.new(@account).call(chain_nonce: caught_up && !lagging ? chain_nonce : nil, reorg_seen: @reorg_seen)
      @account.update!(synced_at: Time.current)

      Result.new(@account.synced_block, caught_up, new_events)
    end

    # A receipt the client pointed at. Only logs of this fund's Safe and token are read from it, so
    # a claimed hash can add nothing the chain does not show. Returns the receipt, or nil.
    def ingest_receipt(tx_hash)
      receipt = @rpc.get_receipt(tx_hash)
      return nil unless receipt

      relevant = receipt[:logs].select { |log| relevant_log?(log) }
      ChainEvent.transaction { relevant.each { |log| store(log) } }
      receipt
    end

    private

    def finalized_block(head)
      block = begin
        @rpc.get_block("finalized")
      rescue Rpc::Error
        nil
      end
      number = block ? block[:number] : head - @chain.confirmations
      [ number, head ].min
    end

    def check_stored_rows(head)
      # A lagging endpoint says nothing about a block above its head.
      rows = @account.chain_events.unfinalized.where(block_number: ..head).distinct.pluck(:block_number, :block_hash)
      return if rows.empty?

      # In one request: anyone can add rows by sending dust, and that must not add requests (SECURITY_REVIEW M4).
      blocks = @rpc.get_blocks(rows.map(&:first).uniq)
      rows.each do |number, hash|
        block = blocks[number] || raise(Rpc::InvalidResponse, "blok ontbreekt")
        next if block[:hash] == hash

        @account.chain_events.unfinalized.where(block_number: number, block_hash: hash).destroy_all
        rewind_to(number - 1)
      end
    end

    # A reorg can also add logs at heights where we stored none, which only the cursor hash reveals.
    def check_cursor(finalized, head)
      cursor = @account.synced_block
      return if cursor.nil? || @account.synced_block_hash.nil? || cursor <= finalized || cursor > head

      block = @rpc.get_block(cursor) || raise(Rpc::InvalidResponse, "blok ontbreekt")
      rewind_to(finalized) unless block[:hash] == @account.synced_block_hash
    end

    def rewind_to(number)
      @reorg_seen = true
      return if @account.synced_block && @account.synced_block <= number

      @account.update!(synced_block: number, synced_block_hash: nil)
    end

    def scan(head)
      from = (@account.synced_block || (head - @chain.confirmations)) + 1
      range = MAX_RANGE
      chunks = 0
      new_events = 0

      while from <= head
        return [ new_events, false ] if chunks >= MAX_CHUNKS_PER_RUN

        to = [ from + range - 1, head ].min
        begin
          logs = fetch_logs(from, to)
        rescue Rpc::RangeTooLarge
          raise if range == 1

          range = [ range / 2, 1 ].max
          next
        end
        new_events += store_chunk(logs, to)
        from = to + 1
        chunks += 1
      end
      [ new_events, true ]
    end

    def fetch_logs(from, to)
      safe_topic = address_topic(@safe)
      safe_logs = @rpc.get_logs(address: @safe, topics: [ SAFE_TOPICS ], from_block: from, to_block: to)
      incoming = @rpc.get_logs(address: @token, topics: [ TRANSFER, nil, safe_topic ], from_block: from, to_block: to)
      outgoing = @rpc.get_logs(address: @token, topics: [ TRANSFER, safe_topic ], from_block: from, to_block: to)

      (safe_logs + incoming + outgoing).uniq { |log| [ log[:tx_hash], log[:log_index] ] }.reject { |log| log[:removed] }.each do |log|
        raise Rpc::InvalidResponse, "log buiten bereik" unless log[:block_number].between?(from, to) && relevant_log?(log)
      end
    end

    def store_chunk(logs, to)
      end_block = @rpc.get_block(to) || raise(Rpc::InvalidResponse, "blok ontbreekt")
      preload_timestamps(logs)
      count = 0
      ChainEvent.transaction do
        logs.each { |log| count += 1 if store(log) }
        @account.update!(synced_block: to, synced_block_hash: end_block[:hash])
      end
      count
    end

    # Decides the filter again locally. RPC filters are a performance measure, not a trust boundary.
    def relevant_log?(log)
      topics = log[:topics]
      if log[:address] == @safe
        SAFE_TOPICS.include?(topics[0])
      elsif log[:address] == @token
        topics[0] == TRANSFER && topics.length == 3 && [ topics[1], topics[2] ].include?(address_topic(@safe))
      else
        false
      end
    end

    # Returns the attributes-derived event, or nil when the log is deliberately not recorded.
    def store(log)
      attributes = parse(log)
      return nil unless attributes

      occurred_at = timestamp(log[:block_number])
      # Not through the association: an unsaved row in its target would autosave with the fund.
      event = ChainEvent.find_or_initialize_by(account_id: @account.id, chain_id: @chain.chain_id, tx_hash: log[:tx_hash], log_index: log[:log_index])
      fresh = event.new_record?
      event.assign_attributes(attributes.merge(block_number: log[:block_number], block_hash: log[:block_hash], occurred_at: occurred_at))
      event.user_id = attribute_to_user(event) if fresh
      # A savepoint: a concurrent insert of the same log must not abort the whole chunk.
      ChainEvent.transaction(requires_new: true) { event.save! }
      fresh ? event : nil
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def parse(log)
      topics = log[:topics]
      case topics[0]
      when TRANSFER then parse_transfer(log)
      when SAFE_RECEIVED then parse_safe_received(log)
      when EXECUTION_SUCCESS then { kind: "execution_success", safe_tx_hash: topics.fetch(1) }
      when EXECUTION_FAILURE then { kind: "execution_failure", safe_tx_hash: topics.fetch(1) }
      when ADDED_OWNER then { kind: "owner_added", to_address: topic_address(topics.fetch(1)) }
      when REMOVED_OWNER then { kind: "owner_removed", from_address: topic_address(topics.fetch(1)) }
      when CHANGED_THRESHOLD then { kind: "threshold_changed", amount: decode_uint(log[:data]) }
      end
    rescue KeyError, IndexError
      raise Rpc::InvalidResponse, "log-topics"
    end

    # Anyone can make a token emit a zero-value Transfer "from" any address (address poisoning),
    # so those never become events. A self-transfer moves nothing.
    def parse_transfer(log)
      from = topic_address(log[:topics].fetch(1))
      to = topic_address(log[:topics].fetch(2))
      amount = decode_uint(log[:data])
      return nil if amount.zero? || from == to

      { kind: to == @safe ? "token_in" : "token_out", from_address: from, to_address: to, token_address: @token, amount: amount }
    end

    # A rejection emits SafeReceived(safe, 0). That is not a contribution.
    def parse_safe_received(log)
      sender = topic_address(log[:topics].fetch(1))
      amount = decode_uint(log[:data])
      return nil if amount.zero? || sender == @safe

      { kind: "native_in", from_address: sender, to_address: @safe, amount: amount }
    end

    def topic_address(topic)
      Abi.decode_address(Hex.to_bin(topic))
    rescue Abi::DecodeError
      raise Rpc::InvalidResponse, "log-adres"
    end

    def decode_uint(data)
      Abi.decode_one("uint256", data)
    rescue Abi::DecodeError
      raise Rpc::InvalidResponse, "log-data"
    end

    def address_topic(address)
      "0x#{address.delete_prefix('0x').rjust(64, '0')}"
    end

    def preload_timestamps(logs)
      missing = logs.map { |log| log[:block_number] }.uniq - @timestamps.keys
      return if missing.size < 2

      @rpc.get_blocks(missing).each { |number, block| @timestamps[number] = Time.zone.at(block[:timestamp]) if block }
    end

    def timestamp(number)
      @timestamps[number] ||= begin
        block = @rpc.get_block(number) || raise(Rpc::InvalidResponse, "blok ontbreekt")
        Time.zone.at(block[:timestamp])
      end
    end

    # By the wallet verified at the moment of the event, and only within this fund: a sender who
    # linked the address later, or who is not a member, stays an unknown sender.
    def attribute_to_user(event)
      address = { "token_in" => event.from_address, "native_in" => event.from_address, "token_out" => event.to_address }[event.kind]
      return nil unless address

      user_id = Wallet.active_at(event.occurred_at).where(address: address).pick(:user_id)
      user_id if user_id && @account.account_memberships.active.where(user_id: user_id).where("COALESCE(joined_at, created_at) <= ?", event.occurred_at).exists?
    end
  end
end

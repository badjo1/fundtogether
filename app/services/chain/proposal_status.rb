module Chain
  # Whether a proposal can execute right now. Computed from live owners, threshold and nonce on
  # every call and never stored: lowering a threshold can make an old partial set sufficient.
  class ProposalStatus
    def initialize(proposal, snapshot, context: nil)
      @proposal = proposal
      @account = proposal.account
      @snapshot = snapshot
      @context = context || ProposalContext.new(@account, snapshot)
    end

    def as_json(*)
      return closed_json unless @proposal.open?

      signers = valid_signers
      why = reason(signers)
      { available: true, executable: why.nil?, reason: why,
        owners: @snapshot.owners, threshold: @snapshot.threshold, current_nonce: @snapshot.nonce.to_s,
        valid_signers: signers, valid_signature_count: signers.length,
        missing_signatures: [ @snapshot.threshold - signers.length, 0 ].max, stale_signers: stale_signers(signers),
        siblings: @context.siblings_of(@proposal), warnings: warnings, fund_balance: fund_balance&.to_s }
    end

    # Validity against the live owners is computed every time. The recovery behind it runs once per row.
    def valid_signers
      signatures.filter_map { |row| row.signer_address if signer_valid?(row) }
    end

    def reason(signers = valid_signers)
      return "not_open" unless @proposal.open?
      return "tampered" unless @proposal.intact? && policy_ok?
      return "nonce_passed" if @proposal.nonce.to_i < @snapshot.nonce
      return "waiting_for_earlier_nonce" if @proposal.nonce.to_i > @snapshot.nonce
      return "calldata_stale" unless rebuilds_identically?
      return "not_enough_signatures" if signers.length < @snapshot.threshold
      return "balance_unknown" if pays_out? && fund_balance.nil?

      "insufficient_balance" if over_balance?
    end

    private

    # Nothing to recover or read for a proposal that is over: the page shows its stored outcome.
    def closed_json
      { available: true, executable: false, reason: "not_open", owners: @snapshot.owners, threshold: @snapshot.threshold,
        current_nonce: @snapshot.nonce.to_s, valid_signers: [], valid_signature_count: 0, missing_signatures: 0,
        stale_signers: [], siblings: [], warnings: [], fund_balance: nil }
    end

    def pays_out?
      %w[transfer_token transfer_native].include?(@proposal.kind)
    end

    def fund_balance
      return nil unless pays_out?

      @proposal.kind == "transfer_token" ? @context.token_balance : @context.native_balance
    end

    def over_balance?
      pays_out? && fund_balance && fund_balance < @proposal.params["amount"].to_i
    end

    def signatures
      @signatures ||= @proposal.safe_signatures.to_a
    end

    def signer_valid?(row)
      @snapshot.owner?(row.signer_address) && row.verified_for?(recomputed_hash)
    end

    def recomputed_hash
      @recomputed_hash ||= @proposal.recomputed_safe_tx_hash
    end

    def stale_signers(signers)
      signatures.map(&:signer_address) - signers
    end

    def policy_ok?
      tx = { to: @proposal.to, value: @proposal.value, data: @proposal.data, operation: @proposal.operation,
             nonce: @proposal.nonce.to_i }
      SafePolicy.violation(tx, safe: @account.safe_address, token: @account.token_address, current_nonce: 0).nil?
    end

    # prev_owner and owner membership were derived from the list at proposal time. If that list has
    # moved, the signed calldata would revert on-chain, so it is not offered for execution.
    def rebuilds_identically?
      return true unless SafeProposal::OWNER_KINDS.include?(@proposal.kind)

      rebuilt = ProposalBuilder.build(kind: @proposal.kind, params: @proposal.params, safe: @account.safe_address,
                                      token: @account.token_address, owners: @snapshot.owners,
                                      threshold: @snapshot.threshold, current_nonce: @snapshot.nonce)
      rebuilt.data == @proposal.data
    rescue Refusal
      false
    end

    def warnings
      list = []
      list << "sibling_at_same_nonce" if @context.siblings_of(@proposal).any?
      list << "lowers_threshold" if lowers_threshold?
      list << "insufficient_balance" if over_balance?
      list << "nonce_gap" if @proposal.nonce.to_i > @snapshot.nonce && @context.gap_before?(@proposal)
      list
    end

    def lowers_threshold?
      new_threshold = @proposal.params["threshold"]
      new_threshold.is_a?(Integer) && new_threshold < @snapshot.threshold
    end
  end
end

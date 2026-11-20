module Chain
  # Derives each proposal's state from chain events and the chain nonce, in both directions: an
  # execution event always wins, and a reorg that removes the event reopens the proposal.
  class ProposalReconciler
    def initialize(account)
      @account = account
    end

    # A lower nonce from one endpoint reopens a superseded proposal only when this sync saw a reorg by block hash.
    # Otherwise it is an endpoint behind the others, and a nonce does not go backwards.
    # chain_nonce nil means the scan has not reached the head, so "the nonce moved without an event
    # we have seen" cannot be concluded yet: only event-based changes are applied.
    def call(chain_nonce:, reorg_seen: false)
      @reorg_seen = reorg_seen
      events = @account.chain_events.where(kind: ChainEvent::EXECUTION_KINDS).index_by(&:safe_tx_hash)
      live_hashes = @account.safe_proposals.where.not(state: "cancelled").pluck(:safe_tx_hash).to_set
      # An execution event is proof its nonce is spent, also for the other proposals at that nonce.
      spent_nonces = @account.safe_proposals.where(safe_tx_hash: events.keys).pluck(:nonce).to_set

      @account.safe_proposals.find_each do |proposal|
        event = events[proposal.safe_tx_hash]
        # A cancelled row left its hash to an identical new proposal. Without one, the chain overrules the app.
        next if proposal.cancelled? && (event.nil? || live_hashes.include?(proposal.safe_tx_hash))

        if event
          event.update!(safe_proposal: proposal) if event.safe_proposal_id != proposal.id
          apply_event(proposal, event)
        elsif chain_nonce
          apply_nonce(proposal, chain_nonce)
        elsif proposal.open? && spent_nonces.include?(proposal.nonce)
          proposal.update!(state: "superseded", execution_tx_hash: nil, executed_at: nil)
        elsif %w[executed failed].include?(proposal.state)
          reopen(proposal)
        end
      end
    end

    private

    def apply_event(proposal, event)
      proposal.update!(state: event.kind == "execution_success" ? "executed" : "failed",
                       execution_tx_hash: event.tx_hash, executed_at: event.occurred_at)
    end

    def apply_nonce(proposal, chain_nonce)
      if proposal.nonce.to_i < chain_nonce
        proposal.update!(state: "superseded", execution_tx_hash: nil, executed_at: nil)
      elsif proposal.state != "superseded" || @reorg_seen
        reopen(proposal)
      end
    end

    # Withdrawn before it was executed: if a reorg undoes the execution, it is withdrawn again, not open.
    def reopen(proposal)
      proposal.update!(state: proposal.cancelled_at ? "cancelled" : "open", execution_tx_hash: nil, executed_at: nil)
    end
  end
end

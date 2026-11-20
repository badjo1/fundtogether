module Chain
  # Withdraws a proposal inside the app. Off-chain only: signatures already given stay valid on the chain until
  # the nonce passes, so the page says so, and a real execution still overrules this (ProposalReconciler).
  class ProposalCancellation
    # Everything still open from someone leaving a fund. They should not keep a say, or a place in the queue.
    def self.for_departed(account, user, by:)
      account.safe_proposals.open.where(proposer: user).includes(:safe_signatures).map do |proposal|
        new(proposal, by: by).force!
        proposal
      end
    end

    def initialize(proposal, by:)
      @proposal = proposal
      @user = by
    end

    def call
      raise Refusal.new("proposal_not_open", status: :conflict) unless @proposal.open?

      account = @proposal.account
      admin = account.active_admin?(@user)
      unless admin || @proposal.proposer_id == @user.id
        raise Refusal.new("cancel_forbidden", status: :forbidden)
      end
      if !admin && @proposal.safe_signatures.where.not(user_id: @user.id).exists?
        raise Refusal.new("cancel_signed_needs_admin", status: :forbidden)
      end

      force!
      @proposal
    end

    def force!
      @proposal.with_lock do
        next unless @proposal.open?

        @proposal.update!(state: "cancelled", cancelled_at: Time.current, cancelled_by: @user)
      end
    end
  end
end

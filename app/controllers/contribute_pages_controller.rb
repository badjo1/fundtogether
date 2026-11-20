class ContributePagesController < FundPagesController
  def show
    @chain = @account.chain
    @linked_addresses = current_user.wallets.active.pluck(:address)
    load_recent
  end

  # Only chain events: a contribution appears here because the sync saw it, never because a client said so.
  def recent
    @chain = @account.chain
    load_recent
    render layout: false
  end

  private

  def load_recent
    @recent = @account.chain_events.includes(:user).where(kind: ChainEvent::CONTRIBUTION_KINDS, user: current_user)
                      .recent_first.limit(5)
  end
end

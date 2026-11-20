# Lazy turbo frames with live chain reads. Each answers in Dutch on every state, including an outage.
class LiveController < FundPagesController
  layout false

  rate_limit to: 60, within: 1.minute, by: -> { current_user&.id || request.remote_ip }, name: "frames",
             with: -> { render_rate_limited_frame("attention") }, only: :attention

  def balance
    @size = params[:size] == "hero" ? "hero" : "tile"
    @frame_id = params[:frame].to_s.match?(/\A[a-z0-9_]{1,40}\z/) ? params[:frame] : "balance_#{@account.id}"
    @chain = @account.chain
    @balance = @account.safe_active? ? Chain::Balance.read(@account) : nil
  end

  def owners
    @snapshot = snapshot_or_nil
    @owners = @snapshot ? @account.owner_details(@snapshot.owners) : []
    @singleton = read_singleton if @snapshot
  end

  # What needs this user now: approvals, and owners who no longer map to a member or wallet.
  def attention
    @gaps_only = params[:gaps] == "1"
    @snapshot = snapshot_or_nil
    views = @snapshot && !@gaps_only ? ProposalView.open_for(@account, current_user, @snapshot) : []
    @views = views.select(&:needs_me?)
    @ready = views.select(&:ready?)
    @gaps = @snapshot ? @account.owner_details(@snapshot.owners).reject { |owner| owner[:active_member] } : []
  end

  private

  def read_singleton
    Chain::SafeReader.for_account(@account).singleton
  rescue Chain::Rpc::Error
    nil
  end
end

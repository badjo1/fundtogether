class SyncRequestsController < ChainApiController
  before_action :set_fund
  before_action :require_fund_contributor
  before_action :require_active_safe
  rate_limit to: 10, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create

  # A hint only: the job looks at the chain, and nothing is credited because someone asked.
  def create
    hash = params[:tx_hash].presence
    down = hash.is_a?(String) ? hash.downcase : hash
    raise Chain::Refusal.new("invalid_tx_hash") if hash && !Chain::Hex.hash?(down)

    ChainSyncJob.perform_later(@account.id, tx_hash: down)
    render json: { status: "queued" }, status: :accepted
  end
end

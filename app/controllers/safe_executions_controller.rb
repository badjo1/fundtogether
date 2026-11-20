class SafeExecutionsController < ChainApiController
  include ProposalRendering

  before_action :set_fund
  before_action :require_fund_contributor
  rate_limit to: 30, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create

  def create
    proposal = find_proposal(:proposal_id)
    result = Chain::ExecutionCheck.new(proposal).call(params[:tx_hash])
    ChainSyncJob.perform_later(@account.id)
    render json: proposal_json(proposal.reload, live_snapshot).merge(execution_check: result),
           status: result == "pending" ? :accepted : :ok
  end
end

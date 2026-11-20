class SafeSignaturesController < ChainApiController
  include ProposalRendering

  before_action :set_fund
  before_action :require_fund_contributor
  rate_limit to: 30, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create

  def create
    proposal = find_proposal(:proposal_id)
    Chain::SignatureRecorder.new(proposal: proposal, user: current_user).call(params[:signature])
    render json: proposal_json(proposal.reload, live_snapshot), status: :created
  end
end

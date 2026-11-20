class SafeProposalsController < ChainApiController
  include ProposalRendering

  before_action :set_fund
  before_action :require_fund_contributor, only: [ :create, :destroy ]
  rate_limit to: 20, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create
  rate_limit to: 20, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :destroy, name: "cancel"
  rate_limit to: 30, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :index, name: "index"

  PAGE_SIZE = 25

  def index
    page = page_param
    proposals = @account.safe_proposals.includes(:proposer, safe_signatures: :user).order(nonce: :desc, id: :desc)
                        .limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE).to_a
    snapshot = live_snapshot
    render json: { proposals: proposals.first(PAGE_SIZE).map { |proposal| proposal_json(proposal, snapshot) },
                   page: page, next_page: proposals.length > PAGE_SIZE ? page + 1 : nil }
  end

  def show
    render json: proposal_json(find_proposal, live_snapshot)
  end

  def create
    raw = params[:params]
    proposal = Chain::ProposalCreator.new(account: @account, proposer: current_user).call(
      kind: params[:kind].to_s, title: params[:title],
      params: raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.to_h : raw,
      acknowledge_risk: params[:acknowledge_risk]
    )
    render json: proposal_json(proposal, live_snapshot), status: :created
  end

  # Inside the app only. Signatures already given stay valid on-chain until the nonce passes.
  def destroy
    proposal = Chain::ProposalCancellation.new(find_proposal, by: current_user).call
    render json: proposal_json(proposal.reload, live_snapshot)
  end
end

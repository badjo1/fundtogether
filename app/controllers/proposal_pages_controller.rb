# Voorstellen: pages over the same services as the JSON API. Forms go to the server, which builds the
# calldata from typed parameters. Signing and executing happen in the browser against the chain.
class ProposalPagesController < FundPagesController
  FORM_KINDS = %w[transfer_token transfer_native add_owner remove_owner swap_owner change_threshold].freeze
  RECIPIENT_KINDS = %w[transfer_token transfer_native].freeze
  FILTERS = %w[needs_me ready waiting insufficient executed failed superseded cancelled stale].freeze
  # Rendered from a fresh chain read, so a loop on these spends our RPC budget and a Puma thread.
  LIVE_FRAMES_PER_MINUTE = 60

  rate_limit to: 20, within: 1.minute, by: -> { current_user&.id || request.remote_ip },
             with: -> { redirect_to dashboard_path, alert: "Te veel verzoeken. Probeer het over een minuut opnieuw." },
             only: [ :create, :reject, :cancel, :renumber ]
  rate_limit to: LIVE_FRAMES_PER_MINUTE, within: 1.minute, by: -> { current_user&.id || request.remote_ip }, name: "frames",
             with: -> { render_rate_limited_frame(action_name == "list" ? "proposal_list" : "proposal_live") },
             only: [ :list, :live ]

  before_action :require_active_safe
  before_action :require_contributor, only: [ :new, :create, :reject, :cancel, :renumber ]
  before_action :set_chain
  before_action :set_proposal, only: [ :show, :live, :reject, :cancel, :renumber ]

  def index
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : nil
  end

  # The list itself is a frame, so a slow RPC never hides the page. Without live data, stored state
  # stays visible and nothing is called ready.
  def list
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : nil
    @page = page_param
    @snapshot = snapshot_or_nil
    @open_views = ProposalView.open_for(@account, current_user, @snapshot)
    closed_state = ProposalView::CLOSED_STATES.include?(@filter) ? @filter : nil
    closed = @filter.nil? || closed_state ? ProposalView.closed_for(@account, current_user, @snapshot, page: @page, state: closed_state) : []
    @next_page = closed.length > ProposalView::CLOSED_PAGE_SIZE
    @closed_views = closed.first(ProposalView::CLOSED_PAGE_SIZE)
    @counts = @open_views.group_by(&:bucket).transform_values(&:size).merge(@account.safe_proposals.where(state: ProposalView::CLOSED_STATES).group(:state).count)
    render layout: false
  end

  def new
    @kind = FORM_KINDS.include?(params[:kind]) ? params[:kind] : nil
    return unless @kind

    load_form_data
    read_recipient_from_link
  end

  def create
    @kind = FORM_KINDS.include?(params[:kind]) ? params[:kind] : nil
    return redirect_to new_account_proposal_page_path(@account) unless @kind

    proposal = Chain::ProposalCreator.new(account: @account, proposer: current_user).call(
      kind: @kind, title: params[:title], params: typed_params, acknowledge_risk: params[:acknowledge_risk] == "1"
    )
    redirect_to account_proposal_page_path(@account, proposal), notice: "Voorstel aangemaakt. Nu kunnen de ondertekenaars het controleren."
  rescue Chain::Amount::Invalid, Chain::Refusal => e
    render_form_with_error(e.message)
  rescue Chain::Rpc::Error
    render_form_with_error(ChainApiController::RPC_MESSAGE)
  end

  def show
    @can_contribute = @membership.admin? || @membership.member?
  end

  def live
    @snapshot = snapshot_or_nil
    @view = ProposalView.new(@proposal, current_user.wallets.active.pluck(:address), @snapshot)
    @linked_addresses = current_user.wallets.active.pluck(:address)
    @can_cancel = @proposal.cancellable_by?(current_user, @membership)
    @can_contribute = @membership.admin? || @membership.member?
    @owners = @snapshot ? @account.owner_details(@snapshot.owners) : []
    render layout: false
  end

  # A rejection is a zero-value self-call at the same nonce: whichever executes first wins.
  def reject
    title = "Afwijzing: #{@proposal.title}".truncate(SafeProposal::TITLE_MAX)
    rejection = Chain::ProposalCreator.new(account: @account, proposer: current_user).call(
      kind: "rejection", title: title, params: { "nonce" => @proposal.nonce.to_i.to_s }
    )
    redirect_to account_proposal_page_path(@account, rejection), notice: "Afwijzing aangemaakt. Deze moet net zo goedgekeurd worden als een voorstel."
  rescue Chain::Refusal => e
    redirect_to account_proposal_page_path(@account, @proposal), alert: e.message
  rescue Chain::Rpc::Error
    redirect_to account_proposal_page_path(@account, @proposal), alert: ChainApiController::RPC_MESSAGE
  end

  # Off-chain, and it says so: signatures already given stay valid until the nonce passes.
  def cancel
    signed = @proposal.safe_signatures.any?
    Chain::ProposalCancellation.new(@proposal, by: current_user).call
    if signed
      flash[:warning] = "Voorstel ingetrokken. Handtekeningen die al zijn gezet blijven geldig op de blockchain totdat dit volgnummer voorbij is. Wil je dat uitsluiten, voer dan een afwijzing uit."
    else
      flash[:notice] = "Voorstel ingetrokken."
    end
    redirect_to account_proposal_page_path(@account, @proposal)
  rescue Chain::Refusal => e
    redirect_to account_proposal_page_path(@account, @proposal), alert: e.message
  end

  # A cancel can leave a later proposal waiting for a nonce nothing will fill. Same content, free nonce.
  def renumber
    snapshot = Chain::SafeReader.for_account(@account).snapshot
    status = Chain::ProposalStatus.new(@proposal, snapshot).as_json
    raise Chain::Refusal.new("renumber_not_needed", status: :conflict) unless status[:warnings].include?("nonce_gap") && @proposal.cancellable_by?(current_user, @membership)

    Chain::ProposalCancellation.new(@proposal, by: current_user).call
    replacement = Chain::ProposalCreator.new(account: @account, proposer: current_user).call(
      kind: @proposal.kind, title: @proposal.title, params: @proposal.params
    )
    redirect_to account_proposal_page_path(@account, replacement), notice: "Voorstel opnieuw gemaakt op volgnummer #{replacement.nonce.to_i}. Eerdere goedkeuringen gelden hier niet voor."
  rescue Chain::Refusal => e
    redirect_to account_proposal_page_path(@account, @proposal), alert: e.message
  rescue Chain::Rpc::Error
    redirect_to account_proposal_page_path(@account, @proposal), alert: ChainApiController::RPC_MESSAGE
  end

  private

  def require_active_safe
    return if @account.safe_active?

    redirect_to account_safe_setup_path(@account), alert: "Stel eerst de Safe van dit fonds in. Daarna kun je voorstellen doen."
  end

  def set_chain
    @chain = @account.chain
  end

  def set_proposal
    @proposal = @account.safe_proposals.includes(:proposer, safe_signatures: :user).find_by(id: params[:id])
    render_not_found unless @proposal
  end

  # Decimal strings and small integers only. Amounts never pass through a float.
  def typed_params
    case @kind
    when "transfer_token" then { "recipient" => recipient, "amount" => Chain::Amount.parse(params[:amount], @chain.token.decimals).to_s }
    when "transfer_native" then { "recipient" => recipient, "amount" => Chain::Amount.parse(params[:amount], 18).to_s }
    when "add_owner" then { "owner" => params[:owner].to_s, "threshold" => params[:threshold].to_s }
    when "remove_owner" then { "owner" => params[:owner].to_s, "threshold" => params[:threshold].to_s }
    when "swap_owner" then { "old_owner" => params[:old_owner].to_s, "new_owner" => params[:new_owner].to_s }
    when "change_threshold" then { "threshold" => params[:threshold].to_s }
    end
  end

  def recipient
    params[:recipient_choice].present? && params[:recipient_choice] != "other" ? params[:recipient_choice].to_s : params[:recipient].to_s.strip
  end

  def load_form_data
    @snapshot = snapshot_or_nil
    @owners = @snapshot ? @account.owner_details(@snapshot.owners) : []
    memberships = @account.account_memberships.active.includes(user: :wallets).order(:id)
    @member_wallets = memberships.filter_map do |membership|
      wallet = membership.user.wallets.select(&:active?).min_by(&:id)
      { user: membership.user, wallet: wallet, viewer: membership.viewer? }
    end
    owner_addresses = @owners.map { |owner| owner[:address] }
    @new_owner_options = @member_wallets.select do |row|
      row[:wallet] && !row[:viewer] && row[:user].email_confirmed? && !owner_addresses.include?(row[:wallet].address)
    end
    @without_wallet = @member_wallets.select { |row| row[:wallet].nil? && !row[:viewer] }
  end

  # The off-ramp links here with ?recipient=. Anyone can craft that URL, so it only fills the form: the page
  # shows the address in full, says whether it is one of your own wallets, and never submits by itself.
  def read_recipient_from_link
    return unless RECIPIENT_KINDS.include?(@kind) && params[:recipient].present?

    address = Chain::Address.normalize(params[:recipient].to_s.strip)
    is_member_wallet = @member_wallets.any? { |row| row[:wallet]&.address == address }
    @recipient_link = { address: address, own: current_user.wallets.active.exists?(address: address),
                        choice: is_member_wallet ? address : "other" }
  rescue Chain::Address::Invalid
    @recipient_link_invalid = true
  end

  def render_form_with_error(message)
    @error = message
    load_form_data
    render :new, status: :unprocessable_entity
  end
end

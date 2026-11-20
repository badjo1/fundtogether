# The way in and out of a fund: link-outs and instructions only. FundTogether holds nothing here and no
# provider ever sees a fund's multisig. See docs/RAMPS.md and docs/ARCHITECTURE.md (Decisions).
class RampsController < FundPagesController
  DIRECTIONS = %w[on off].freeze

  before_action :set_guide
  before_action :require_contributor, only: :leave

  def show
    @direction = DIRECTIONS.include?(params[:direction]) ? params[:direction] : "on"
    @wallets = current_user.wallets.active.order(:id)
  end

  # The interstitial before a provider. The route id is looked up within this fund's chain and token,
  # so this page cannot be made to link anywhere else.
  def leave
    @route = @guide.route(params[:route].to_s)
    render_not_found unless @route&.url
  end

  private

  def set_guide
    @guide = Ramps::FundGuide.new(@account)
    @can_act = @membership.admin? || @membership.member?
  end
end

# GET only describes the handoff (link previews and scanners fetch URLs, so a GET must not spend
# it). POST spends it, after the person confirmed the name on screen. A phone opening the QR gets the
# HTML confirmation page; the JSON answers stay as in docs/ARCHITECTURE.md.
class WalletHandoffRedemptionsController < ChainApiController
  include WalletHandoffAccess

  allow_unauthenticated_access
  rate_limit to: 20, within: 1.minute, with: -> { rate_limited }

  rescue_from ActionController::InvalidAuthenticityToken do
    if request.format.html?
      render_invalid_page("Vernieuw de pagina en probeer het opnieuw.")
    else
      render_error("invalid_csrf", "Vernieuw de pagina en probeer het opnieuw.", status: :unprocessable_entity)
    end
  end

  def show
    response.headers["Cache-Control"] = "no-store"
    respond_to do |format|
      format.html { show_page }
      format.json { show_json }
    end
  end

  def create
    response.headers["Cache-Control"] = "no-store"
    challenge = WalletChallenge.find_handoff(params[:token])
    spent = challenge && !challenge.consumed? && !challenge.expired? && challenge.consume!

    respond_to do |format|
      format.html do
        next render_invalid_page unless spent

        start_handoff_grant(challenge)
        redirect_to wallet_handoff_path(params[:token]), status: :see_other
      end
      format.json do
        raise Chain::Refusal.new("handoff_invalid", status: :not_found) unless spent

        start_handoff_grant(challenge)
        render json: { name: challenge.user.display_name, scope: "wallet_linking",
                       grant_expires_at: WalletChallenge::HANDOFF_GRANT_LIFETIME.from_now.utc.iso8601 }, status: :created
      end
    end
  end

  private

  def show_json
    challenge = usable_handoff
    render json: { name: challenge.user.display_name, expires_at: challenge.expires_at.utc.iso8601,
                   scope: "wallet_linking" }
  end

  # Unspent: ask for confirmation. Spent by this very browser: the linking page, which only talks to
  # endpoints the grant already opens. Anyone else with the URL sees that the link is used up.
  def show_page
    challenge = WalletChallenge.find_handoff(params[:token])
    if challenge && !challenge.consumed? && !challenge.expired?
      @challenge = challenge
      render :show
    elsif challenge && cookies.encrypted[COOKIE] == challenge.id && challenge.handoff_grant_active?
      @challenge = challenge
      @user = challenge.user
      render :linking
    else
      render_invalid_page
    end
  end

  def render_invalid_page(message = Chain::Refusal::MESSAGES.fetch("handoff_invalid"))
    @message = message
    render :invalid, status: :not_found, formats: :html
  end

  def usable_handoff
    challenge = WalletChallenge.find_handoff(params[:token])
    return challenge if challenge && !challenge.consumed? && !challenge.expired?

    raise Chain::Refusal.new("handoff_invalid", status: :not_found)
  end
end

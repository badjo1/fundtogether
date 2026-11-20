# Base for the HTML pages of one fund. Same rule as the JSON API: a fund is only reachable through the
# user's active memberships, and a non-member gets the same 404 as a missing fund.
class FundPagesController < ApplicationController
  before_action :set_fund

  rescue_from Chain::Registry::ChainDisabled do
    redirect_to dashboard_path, alert: "Het netwerk van dit fonds is op dit moment niet beschikbaar in FundTogether."
  end

  private

  def set_fund
    @membership = current_user.active_memberships.includes(:account).find_by(account_id: params[:account_id])
    return render_not_found unless @membership

    @account = @membership.account
    @current_membership = @membership
    remember_current_fund
  end

  # The fund on screen is the fund that invitations and the sidebar act on. A frame load on the
  # dashboard is not a visit: it must not switch funds behind the user's back.
  def remember_current_fund
    return if turbo_frame_request? || prefetch_request? || current_user.current_account_id == @account.id

    current_user.update_column(:current_account_id, @account.id)
  end

  # A hover or a browser's guess is not a visit either (Turbo prefetch, Sec-Purpose).
  def prefetch_request?
    [ request.headers["Sec-Purpose"], request.headers["X-Sec-Purpose"], request.headers["Purpose"] ].compact.any? { |value| value.include?("prefetch") }
  end

  def render_rate_limited_frame(id)
    render html: helpers.turbo_frame_tag(id) { helpers.tag.p("Te veel verzoeken. Probeer het over een minuut opnieuw.", class: "text-sm text-yellow-800 p-4") },
           status: :too_many_requests
  end

  def page_param
    params[:page].to_s.to_i.clamp(1, 100_000)
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false, content_type: "text/html"
  end

  def require_contributor
    return if @membership.admin? || @membership.member?

    redirect_to dashboard_path, alert: "Met alleen leesrechten kun je dit niet doen."
  end

  def require_admin
    redirect_to dashboard_path, alert: "Alleen admins kunnen dit doen." unless @membership.admin?
  end

  def snapshot_or_nil
    return nil unless @account.safe_active?

    Chain::SafeReader.for_account(@account).snapshot
  rescue Chain::Rpc::Error, Chain::Registry::ChainDisabled => e
    Rails.logger.warn("[chain.page] live snapshot: #{e.class}")
    nil
  end
end

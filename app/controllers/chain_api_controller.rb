# Base for the JSON endpoints in docs/ARCHITECTURE.md (Browser/server contract). Answers are JSON,
# errors are { error, message } with Dutch text, and fund access goes through active memberships.
class ChainApiController < ApplicationController
  RPC_MESSAGE = "De blockchain is nu niet bereikbaar. Probeer het later opnieuw.".freeze
  RATE_LIMITED_MESSAGE = "Te veel verzoeken. Probeer het over een minuut opnieuw.".freeze

  rescue_from Chain::Refusal do |error|
    render_error(error.code, error.message, status: error.status)
  end
  rescue_from Chain::Rpc::Error do |error|
    Rails.logger.warn("[chain.api] #{error.class}: #{error.message}")
    render_error("rpc_unavailable", RPC_MESSAGE, status: :service_unavailable)
  end
  rescue_from Chain::Registry::ChainDisabled do
    render_error("chain_not_enabled", Chain::Refusal::MESSAGES.fetch("chain_not_enabled"), status: :unprocessable_entity)
  end
  rescue_from ActionController::InvalidAuthenticityToken do
    render_error("invalid_csrf", "Vernieuw de pagina en probeer het opnieuw.", status: :unprocessable_entity)
  end
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render_error("invalid_json", "Dit verzoek kon niet worden gelezen.", status: :bad_request)
  end

  private

  def render_error(code, message, status:)
    render json: { error: code, message: message }, status: status
  end

  # The HTML app redirects to the login page. A fetch call needs a status.
  def request_authentication
    render_error("not_authenticated", "Log eerst in.", status: :unauthorized)
  end

  def rate_limited
    render_error("rate_limited", RATE_LIMITED_MESSAGE, status: :too_many_requests)
  end

  def page_param
    params[:page].to_s.to_i.clamp(1, 100_000)
  end

  def rate_limit_key
    current_user&.id || request.remote_ip
  end

  # Missing funds and funds you are not an active member of get the same answer.
  def set_fund
    @membership = current_user.active_memberships.includes(:account).find_by(account_id: params[:account_id])
    @account = @membership&.account
    render_error("not_found", "Niet gevonden.", status: :not_found) unless @account
  end

  def require_fund_contributor
    return if @membership.admin? || @membership.member?

    render_error("forbidden", "Met alleen leesrechten kun je dit niet doen.", status: :forbidden)
  end

  def require_fund_admin
    render_error("forbidden", "Alleen admins kunnen dit doen.", status: :forbidden) unless @membership.admin?
  end

  def require_active_safe
    raise Chain::Refusal.new("safe_not_active", status: :conflict) unless @account.safe_active?
  end
end

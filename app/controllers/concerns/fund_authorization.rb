# Every fund action goes through the user's active memberships (docs/ARCHITECTURE.md,
# Authorization). users.current_account_id is only a preference: it grants nothing.
module FundAuthorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :current_account, :current_membership
  end

  private
    def current_user
      resume_session&.user
    end

    def current_membership
      return @current_membership if defined?(@current_membership)

      @current_membership = current_user&.current_membership
    end

    def current_account
      current_membership&.account
    end

    def require_current_account
      return if current_account

      redirect_to new_account_path, alert: flash[:alert] || "Maak eerst een account aan om te beginnen"
    end

    def require_current_admin
      redirect_to dashboard_path, alert: "Alleen admins kunnen dit doen." unless current_membership&.admin?
    end

    # For anything that changes a fund: the form names the fund it was rendered for. A tab left open on fund A
    # must not act on fund B because B was viewed last (docs/SECURITY_REVIEW.md, M9). Sets @fund.
    def require_explicit_fund_admin
      membership = current_user.active_memberships.includes(:account).find_by(account_id: params[:account_id].to_s) if params[:account_id].present?
      return redirect_to(dashboard_path, alert: "We weten niet om welk fonds het gaat. Vernieuw de pagina en probeer het opnieuw.") unless membership
      return redirect_to(dashboard_path, alert: "Alleen admins kunnen dit doen.") unless membership.admin?

      @fund = membership.account
      @current_membership = membership
    end
end

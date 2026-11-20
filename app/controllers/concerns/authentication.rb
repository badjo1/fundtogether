module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      session_row = Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
      return nil unless session_row
      return session_row.destroy && nil unless session_row.usable?

      session_row.seen!
      session_row
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url if request.get? || request.head?
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # A new login gets a new session: nothing a previous visitor left in the cookie
    # (such as a pending invitation) carries over, and a fixed session id stops working.
    def start_new_session_for(user)
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to

      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip, last_seen_at: Time.current).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: Session::ABSOLUTE_LIMIT.from_now }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
      reset_session
    end
end

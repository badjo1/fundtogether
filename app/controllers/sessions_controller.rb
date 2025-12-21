class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user

      # Handle pending invitation if present
      if session[:pending_invitation_token].present?
        invitation = Invitation.find_by(token: session[:pending_invitation_token])
        if invitation&.ready_to_accept?
          invitation.accept!(user)
          session.delete(:pending_invitation_token)
          redirect_to account_path(invitation.account), notice: "Je bent toegevoegd aan #{invitation.account.name}!"
          return
        end
      end

      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end

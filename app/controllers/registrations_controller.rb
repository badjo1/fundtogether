class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def new
    @user = User.new

    # Pre-fill email als via invitation
    if session[:invitation_email].present?
      @user.email_address = session[:invitation_email]
      @from_invitation = true
    end
  end
  
  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user

      # Handle pending invitation if present
      if session[:pending_invitation_token].present?
        invitation = Invitation.find_by(token: session[:pending_invitation_token])
        if invitation&.ready_to_accept?
          invitation.accept!(@user)
          session.delete(:pending_invitation_token)
          session.delete(:invitation_email)
          redirect_to account_path(invitation.account), notice: "Account aangemaakt en toegevoegd aan #{invitation.account.name}!"
          return
        end
      end

      redirect_to after_authentication_url, notice: "Account succesvol aangemaakt"
    else
      @from_invitation = session[:invitation_email].present?
      render :new, status: :unprocessable_entity
    end
  end

 private
  
  def registration_params
    params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  end
  
  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      Current.session = session
      cookies.signed.permanent[:session_token] = { value: session.id, httponly: true }
    end
  end
  
  def after_authentication_url
    dashboard_path
  end

end

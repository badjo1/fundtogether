class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def new
    @user = User.new
  end
  
  def create
    @user = User.new(registration_params)
    
    if @user.save
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Account succesvol aangemaakt"
    else
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

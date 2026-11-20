class RegistrationsController < ApplicationController
  include InvitationAcceptance

  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to register_path, alert: "Te veel pogingen. Probeer het later opnieuw." }

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
      pending_token = session[:pending_invitation_token]
      proof = session[:invitation_email_proof]
      start_new_session_for @user
      apply_email_proof(@user, proof)
      @user.send_email_confirmation unless @user.email_confirmed?

      return if redirect_for_pending_invitation(@user, pending_token, joined_prefix: "Account aangemaakt en toegevoegd aan")

      redirect_to after_authentication_url,
                  notice: @user.email_confirmed? ? "Account aangemaakt." : "Account aangemaakt. Check je inbox om je e-mailadres te bevestigen."
    else
      @from_invitation = session[:invitation_email].present?
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  end

  def after_authentication_url
    dashboard_path
  end
end

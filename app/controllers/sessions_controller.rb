class SessionsController < ApplicationController
  include InvitationAcceptance

  allow_unauthenticated_access only: %i[ new create ]
  TOO_MANY = -> { redirect_to new_session_path, alert: "Te veel pogingen. Probeer het later opnieuw." }
  rate_limit to: 10, within: 3.minutes, only: :create, with: TOO_MANY
  # Per address too, so guessing from many IP addresses stays bounded whatever the proxy forwards.
  rate_limit to: 20, within: 10.minutes, only: :create, name: "login-address", with: TOO_MANY,
             by: -> { params[:email_address].to_s.strip.downcase }

  def new
  end

  def create
    if user = authenticate
      pending_token = session[:pending_invitation_token]
      proof = session[:invitation_email_proof]
      start_new_session_for user
      apply_email_proof(user, proof)

      return if redirect_for_pending_invitation(user, pending_token, joined_prefix: "Je bent toegevoegd aan")

      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Dit e-mailadres of wachtwoord klopt niet."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  # A missing field is a wrong login, not an exception (authenticate_by raises on it).
  def authenticate
    credentials = params.permit(:email_address, :password)
    return nil unless credentials[:email_address].is_a?(String) && credentials[:password].is_a?(String)

    User.authenticate_by(email_address: credentials[:email_address], password: credentials[:password])
  end
end

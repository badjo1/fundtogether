class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  TOO_MANY = -> { redirect_to new_password_path, alert: "Te veel pogingen. Probeer het later opnieuw." }
  rate_limit to: 10, within: 3.minutes, only: :create, with: TOO_MANY
  rate_limit to: 3, within: 10.minutes, only: :create, name: "reset-address", with: TOO_MANY,
             by: -> { params[:email_address].to_s.strip.downcase }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Als dit adres bij ons bekend is, staat er een mail met instructies in je inbox."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      # The reset link went to this address, so this proves it. A squatter who registered it is logged out above.
      @user.confirm_email!
      redirect_to new_session_path, notice: "Je wachtwoord is gewijzigd. Log opnieuw in."
    else
      redirect_to edit_password_path(params[:token]), alert: "De wachtwoorden zijn niet gelijk, of het wachtwoord is te kort."
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Deze resetlink is ongeldig of verlopen."
    end
end

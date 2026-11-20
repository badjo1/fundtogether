# H2 in docs/SECURITY_REVIEW.md. The mail alone is not enough: confirming also needs this account's session or
# password, so a stranger who registers someone's address cannot have the real owner confirm it by a click.
class EmailConfirmationsController < ApplicationController
  include InvitationAcceptance

  TOO_MANY = -> { redirect_to email_confirmation_pending_path, alert: "Te veel pogingen. Probeer het later opnieuw." }

  allow_unauthenticated_access only: %i[ show create ]
  rate_limit to: 3, within: 10.minutes, name: "resend-user", only: :resend, with: TOO_MANY, by: -> { current_user&.id }
  rate_limit to: 10, within: 10.minutes, name: "resend-ip", only: :resend, with: TOO_MANY
  rate_limit to: 20, within: 10.minutes, name: "confirm-ip", only: :create,
             with: -> { redirect_to root_path, alert: "Te veel pogingen. Probeer het later opnieuw." }
  rate_limit to: 5, within: 10.minutes, name: "confirm-token", only: :create, by: -> { params[:token].to_s },
             with: -> { redirect_to root_path, alert: "Te veel pogingen. Probeer het later opnieuw." }

  before_action :set_user_by_token, only: %i[ show create ]

  def pending
    redirect_to(dashboard_path, notice: "Je e-mailadres is al bevestigd.") if current_user.email_confirmed?
  end

  def resend
    if current_user.email_confirmed?
      redirect_to dashboard_path, notice: "Je e-mailadres is al bevestigd."
    else
      current_user.send_email_confirmation
      redirect_to email_confirmation_pending_path, notice: "We hebben de bevestigingsmail opnieuw gestuurd."
    end
  end

  def show
    response.headers["Cache-Control"] = "no-store"
    @own_session = current_user == @user
  end

  def create
    unless current_user == @user || (params[:password].is_a?(String) && @user.authenticate(params[:password]))
      @own_session = false
      flash.now[:alert] = "Dit wachtwoord hoort niet bij dit account. Heb je dit account niet zelf aangemaakt? Laat deze mail dan voor wat hij is."
      return render :show, status: :unprocessable_entity
    end

    pending_token = session.delete(:pending_invitation_token)
    start_new_session_for(@user) unless current_user == @user
    @user.confirm_email!
    session.delete(:invitation_email)

    return if redirect_for_pending_invitation(@user, pending_token, joined_prefix: "E-mailadres bevestigd. Je bent toegevoegd aan")

    invitation = Invitation.active.email_verified.where(email: @user.email_address).order(created_at: :desc).first
    return redirect_to(accept_invitation_path(invitation.token), notice: "E-mailadres bevestigd. Hier is je uitnodiging.") if invitation

    redirect_to dashboard_path, notice: "E-mailadres bevestigd."
  end

  private

  def set_user_by_token
    @user = User.find_by_token_for(:email_confirmation, params[:token].to_s)
    render :invalid, status: :gone unless @user
  end
end

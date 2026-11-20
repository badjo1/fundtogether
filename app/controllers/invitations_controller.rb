# Two kinds of invitation share this flow:
# - Addressed: an admin names the address. Only a user with that address can accept.
# - Bearer link (link/QR/WhatsApp): anyone holding the link can claim it with an address they
#   prove by mail, and joins as `member` under that address. App roles carry no on-chain power.
class InvitationsController < ApplicationController
  include InvitationAcceptance

  TOKEN_ACTIONS = %i[ open request_email_verification verify_email show_accept accept reject send_invitation_email ].freeze
  TOO_MANY_ATTEMPTS = -> { redirect_to root_path, alert: "Te veel pogingen. Probeer het later opnieuw." }
  # Mail with a fund name and inviter name someone chose: limits per person and per fund (SECURITY_REVIEW M2).
  INVITES_PER_USER = 10
  INVITES_PER_FUND = 30

  allow_unauthenticated_access only: %i[ open request_email_verification verify_email show_accept accept reject ]

  rate_limit to: 30, within: 1.minute, name: "token", with: TOO_MANY_ATTEMPTS,
             only: %i[ open verify_email show_accept accept reject ]
  rate_limit to: 3, within: 10.minutes, name: "mail-link", with: TOO_MANY_ATTEMPTS,
             only: :request_email_verification, by: -> { params[:token] }
  rate_limit to: 5, within: 10.minutes, name: "mail-address", with: TOO_MANY_ATTEMPTS,
             only: :request_email_verification, by: -> { params[:email].to_s.strip.downcase }
  rate_limit to: 10, within: 10.minutes, name: "mail-ip", with: TOO_MANY_ATTEMPTS,
             only: :request_email_verification
  rate_limit to: 20, within: 10.minutes, name: "mail-admin", with: TOO_MANY_ATTEMPTS,
             only: :send_invitation_email
  rate_limit to: INVITES_PER_USER, within: 10.minutes, name: "invite-user", with: TOO_MANY_ATTEMPTS,
             only: %i[ create send_invitation_email ], by: -> { current_user&.id }
  rate_limit to: INVITES_PER_FUND, within: 1.day, name: "invite-fund", with: TOO_MANY_ATTEMPTS,
             only: %i[ create send_invitation_email ], by: -> { params[:account_id].presence || Invitation.where(token: params[:token]).pick(:account_id) }

  before_action :require_explicit_fund_admin, only: %i[ create destroy ]
  before_action :set_invitation_by_id, only: :destroy
  before_action :set_invitation_by_token, only: TOKEN_ACTIONS
  before_action :require_admin_of_invitation_fund, only: :send_invitation_email
  before_action :check_invitation_validity, only: TOKEN_ACTIONS
  before_action :require_confirmed_inviter, only: %i[ create send_invitation_email ]

  # POST /invitations - STAP 0: Creëer uitnodiging
  def create
    @invitation = @fund.invitations.build(invitation_params)
    @invitation.invited_by = current_user
    # Een adres dat de admin zelf opgeeft is meteen bevestigd; alleen dat adres kan accepteren.
    @invitation.email_verified_at = Time.current if @invitation.email.present?

    if @invitation.save
      @invitation_url = public_invitation_url(@invitation)

      InvitationMailer.invite(@invitation, @invitation_url).deliver_later if @invitation.email.present?

      remember_latest_invitation(@invitation)

      redirect_to invitation_success_path, notice: "Uitnodiging aangemaakt!"
    else
      redirect_to users_path(account_id: @fund.id), alert: @invitation.errors.full_messages.join(", ")
    end
  end

  # GET /invitations/success - Toon share opties
  def success
    @invitation_url = session.delete(:latest_invitation_url)
    @invitation = Invitation.where(account_id: current_user.active_memberships.admins.select(:account_id))
                            .find_by(id: session.delete(:latest_invitation_id))

    unless @invitation_url && @invitation
      redirect_to users_path, alert: "Geen uitnodiging gevonden."
      return
    end
    @current_membership = current_user.active_memberships.find_by(account_id: @invitation.account_id)

    # Voor WhatsApp share link
    account_name = @invitation.account.name
    @whatsapp_text = "Je bent uitgenodigd voor #{account_name}! #{@invitation_url}"
  end

  # GET /invitations/:token/open - STAP 1: Eerste contact met link
  def open
    # The accept page handles email entry/verification state
    redirect_to accept_invitation_path(@invitation.token)
  end

  # POST /invitations/:token/request_verification - STAP 2a: Email invoeren
  def request_email_verification
    if @invitation.email_verified?
      redirect_to accept_invitation_path(@invitation.token),
                  alert: "Dit emailadres is al bevestigd en kan niet meer worden gewijzigd."
    elsif @invitation.claim_email(params[:email].to_s)
      session[:invitation_email_claim] = { "id" => @invitation.id, "email" => @invitation.email }
      InvitationMailer.verify_email(@invitation).deliver_later

      redirect_to accept_invitation_path(@invitation.token), notice: "Check je inbox voor de verificatie link!"
    else
      redirect_to accept_invitation_path(@invitation.token), alert: "Vul een geldig emailadres in."
    end
  end

  # GET /invitations/:token/verify/:verification_token - STAP 2b: Email verifiëren
  def verify_email
    verification_token = params[:verification_token]

    if Invitation.find_by_email_verification_token(verification_token) == @invitation
      @invitation.verify_email!
      remember_email_proof
      redirect_to accept_invitation_path(@invitation.token),
                  notice: "Email geverifieerd! Je kunt nu de uitnodiging accepteren."
    else
      redirect_to open_invitation_path(@invitation.token),
                  alert: "Verificatie link is ongeldig of verlopen."
    end
  end

  # GET /invitations/:token/accept - STAP 3: Accept/Reject pagina
  # The view handles 3 states: email not known, known but not verified, verified.
  def show_accept
    @invitation_url = public_invitation_url(@invitation)
  end

  # POST /invitations/:token/accept - STAP 4: Daadwerkelijk accepteren
  def accept
    unless @invitation.ready_to_accept?
      redirect_to accept_invitation_path(@invitation.token), alert: "Bevestig eerst je emailadres."
      return
    end

    if current_user
      accept_as_current_user
    else
      # Niet ingelogd → check of user bestaat
      session[:pending_invitation_token] = @invitation.token

      if User.exists?(email_address: @invitation.email)
        redirect_to login_path, notice: "Log in om de uitnodiging te accepteren."
      else
        # Nieuwe user → pre-fill email in registratie
        session[:invitation_email] = @invitation.email
        redirect_to register_path, notice: "Maak een account aan."
      end
    end
  end

  # POST /invitations/:token/reject
  def reject
    if @invitation.rejectable_by?(current_user)
      @invitation.reject!
      session.delete(:pending_invitation_token)
      session.delete(:invitation_email)
      redirect_to root_path, notice: "Uitnodiging geweigerd."
    else
      redirect_to accept_invitation_path(@invitation.token),
                  alert: "Log in met het uitgenodigde emailadres om deze uitnodiging te weigeren."
    end
  end

  # DELETE /invitations/:id
  def destroy
    # Allow deleting pending OR rejected invitations
    if @invitation.pending? || @invitation.rejected?
      @invitation.destroy
      redirect_to users_path(account_id: @fund.id), notice: "Uitnodiging verwijderd."
    else
      redirect_to users_path(account_id: @fund.id), alert: "Kan alleen pending of geannuleerde uitnodigingen verwijderen."
    end
  end

  # POST /invitations/:token/send_email - Helper: direct email versturen (alleen admins)
  def send_invitation_email
    email = params[:email].to_s

    if email.blank?
      remember_latest_invitation(@invitation)
      redirect_to invitation_success_path, alert: "Geen email ingevuld."
    elsif @invitation.address_to(email)
      InvitationMailer.invite(@invitation, public_invitation_url(@invitation)).deliver_later

      redirect_to users_path(account_id: @invitation.account_id), notice: "Uitnodiging verstuurd naar #{@invitation.email}"
    else
      remember_latest_invitation(@invitation)
      redirect_to invitation_success_path, alert: "Vul een geldig emailadres in."
    end
  end

  private

  def accept_as_current_user
    account_name = @invitation.account.name
    apply_email_proof(current_user, session[:invitation_email_proof])

    case join_invitation(current_user, @invitation)
    when :unconfirmed
      session[:pending_invitation_token] = @invitation.token
      redirect_to email_confirmation_pending_path, notice: "Bevestig eerst je e-mailadres. Daarna kun je meedoen met #{account_name}."
    when :joined
      redirect_to dashboard_path, notice: "Je bent toegevoegd aan #{account_name}!"
    when :already_member
      redirect_to dashboard_path, notice: "Je bent al lid van #{account_name}."
    else
      redirect_to accept_invitation_path(@invitation.token),
                  alert: "Deze uitnodiging is bedoeld voor een ander emailadres dan dat van jouw account."
    end
  end

  def remember_latest_invitation(invitation)
    session[:latest_invitation_url] = public_invitation_url(invitation)
    session[:latest_invitation_id] = invitation.id
  end

  def public_invitation_url(invitation)
    open_invitation_url(invitation.token, **PublicUrl.options)
  end

  # Only for the browser that asked for this very mail; see apply_email_proof.
  def remember_email_proof
    claim = session.delete(:invitation_email_claim)
    return unless claim && claim["id"] == @invitation.id && claim["email"] == @invitation.email

    session[:invitation_email_proof] = @invitation.email
  end

  def require_confirmed_inviter
    return if current_user.email_confirmed?

    redirect_to email_confirmation_pending_path, alert: "Bevestig eerst je e-mailadres. Daarna kun je mensen uitnodigen."
  end

  def set_invitation_by_token
    @invitation = Invitation.find_by(token: params[:token])

    invitation_not_found unless @invitation
  end

  def set_invitation_by_id
    @invitation = @fund.invitations.find_by(id: params[:id])

    redirect_to users_path(account_id: @fund.id), alert: "Uitnodiging niet gevonden." unless @invitation
  end

  # Same answer as an unknown token, so a non-admin learns nothing about the invitation.
  def require_admin_of_invitation_fund
    invitation_not_found unless @invitation.account.active_admin?(current_user)
  end

  def invitation_not_found
    redirect_to root_path, alert: "Uitnodiging niet gevonden."
  end

  def check_invitation_validity
    if @invitation.expired?
      render :expired, status: :gone
    elsif @invitation.accepted?
      redirect_to root_path, alert: "Deze uitnodiging is al geaccepteerd."
    elsif @invitation.rejected?
      redirect_to root_path, alert: "Deze uitnodiging is geweigerd."
    end
  end

  def invitation_params
    params.fetch(:invitation, {}).permit(:email)
  end
end

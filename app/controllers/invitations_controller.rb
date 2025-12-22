class InvitationsController < ApplicationController
  before_action :set_invitation_by_token, only: [
    :open, :request_email_verification, :verify_email,
    :show_accept, :accept, :reject, :send_invitation_email
  ]
  before_action :set_invitation_by_id, only: [ :destroy ]
  before_action :check_invitation_validity, only: [ :show_accept, :accept ]

  skip_before_action :verify_authenticity_token, only: [ :open, :verify_email ]
  allow_unauthenticated_access only: [
    :open, :request_email_verification, :verify_email,
    :show_accept, :accept
  ]

  # POST /invitations - STAP 0: Creëer uitnodiging
  def create
    @invitation = current_account.invitations.build(invitation_params)
    @invitation.invited_by = current_user

    if @invitation.save
      @invitation_url = open_invitation_url(@invitation.token)

      # Als email direct meegegeven: stuur email + verifieer automatisch
      if @invitation.email.present?
        @invitation.generate_email_verification_token
        @invitation.save
        InvitationMailer.invite(@invitation, @invitation_url).deliver_later
        # Direct verificatie voor trusted flow
        @invitation.verify_email!
      end

      session[:latest_invitation_url] = @invitation_url
      session[:latest_invitation_id] = @invitation.id

      redirect_to invitation_success_path, notice: "Uitnodiging aangemaakt!"
    else
      redirect_to users_path, alert: @invitation.errors.full_messages.join(", ")
    end
  end

  # GET /invitations/success - Toon share opties
  def success
    @invitation_url = session.delete(:latest_invitation_url)
    @invitation = Invitation.find_by(id: session.delete(:latest_invitation_id))

    unless @invitation_url && @invitation
      redirect_to users_path, alert: "Geen uitnodiging gevonden."
      return
    end

    # Voor WhatsApp share link
    account_name = @invitation.account.name
    @whatsapp_text = "Je bent uitgenodigd voor #{account_name}! #{@invitation_url}"
  end

  # GET /invitations/:token/open - STAP 1: Eerste contact met link
  def open
    if @invitation.expired?
      render :expired, status: :gone
      return
    end

    if @invitation.accepted?
      redirect_to root_path, alert: "Deze uitnodiging is al geaccepteerd."
      return
    end

    # Beslisboom:
    if @invitation.email.present? && @invitation.email_verified?
      # Email al bekend en geverifieerd → direct naar accept/reject
      redirect_to accept_invitation_path(@invitation.token)
    elsif @invitation.email.present? && !@invitation.email_verified?
      # Email bekend maar niet geverifieerd → toon "check je email" pagina
      render :awaiting_verification
    else
      # Geen email → vraag email en stuur verificatie
      render :request_email
    end
  end

  # POST /invitations/:token/request_verification - STAP 2a: Email invoeren
  def request_email_verification
    if @invitation.update(email: params[:email])
      @invitation.generate_email_verification_token
      @invitation.save

      # Stuur verificatie email
      InvitationMailer.verify_email(@invitation).deliver_later

      flash[:notice] = "Check je inbox voor de verificatie link!"
      render :awaiting_verification
    else
      flash.now[:alert] = @invitation.errors.full_messages.join(", ")
      render :request_email, status: :unprocessable_entity
    end
  end

  # GET /invitations/:token/verify/:verification_token - STAP 2b: Email verifiëren
  def verify_email
    verification_token = params[:verification_token]

    if Invitation.find_by_email_verification_token(verification_token) == @invitation
      @invitation.verify_email!
      redirect_to accept_invitation_path(@invitation.token),
                  notice: "Email geverifieerd! Je kunt nu de uitnodiging accepteren."
    else
      redirect_to open_invitation_path(@invitation.token),
                  alert: "Verificatie link is ongeldig of verlopen."
    end
  end

  # GET /invitations/:token/accept - STAP 3: Accept/Reject pagina
  def show_accept
    # Email moet geverifieerd zijn om hier te komen
    unless @invitation.ready_to_accept?
      redirect_to open_invitation_path(@invitation.token),
                  alert: "Verificatie vereist."
    end
  end

  # POST /invitations/:token/accept - STAP 4: Daadwerkelijk accepteren
  def accept
    if current_user
      # User ingelogd → direct accepteren
      @invitation.accept!(current_user)
      redirect_to account_path(@invitation.account),
                  notice: "Je bent toegevoegd aan #{@invitation.account.name}!"
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
    @invitation.reject!
    redirect_to root_path, notice: "Uitnodiging geweigerd."
  end

  # DELETE /invitations/:id
  def destroy
    if @invitation.account == current_account
      @invitation.destroy
      redirect_to users_path, notice: "Uitnodiging geannuleerd."
    else
      redirect_to users_path, alert: "Je kunt deze uitnodiging niet annuleren."
    end
  end

  # POST /invitations/:token/send_email - Helper: direct email versturen
  def send_invitation_email
    email = params[:email]

    if email.present?
      @invitation.update!(email: email)
      @invitation.generate_email_verification_token
      @invitation.save
      InvitationMailer.invite(@invitation, open_invitation_url(@invitation.token)).deliver_later
      @invitation.verify_email! # Auto-verify voor trusted flow

      redirect_to users_path, notice: "Uitnodiging verstuurd naar #{@invitation.email}"
    else
      redirect_to invitation_success_path, alert: "Geen email ingevuld."
    end
  end

  private

  def set_invitation_by_token
    @invitation = Invitation.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Uitnodiging niet gevonden."
  end

  def set_invitation_by_id
    @invitation = Invitation.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: "Uitnodiging niet gevonden."
  end

  def check_invitation_validity
    if @invitation.expired?
      render :expired, status: :gone
      return
    end

    if @invitation.accepted?
      redirect_to root_path, alert: "Deze uitnodiging is al geaccepteerd."
    end
  end

  def invitation_params
    params.fetch(:invitation, {}).permit(:email)
  end
end

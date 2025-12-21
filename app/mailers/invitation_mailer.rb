class InvitationMailer < ApplicationMailer
  # Voor direct email flow (email bekend bij creatie)
  def invite(invitation, invitation_url)
    @invitation = invitation
    @invitation_url = invitation_url
    @account = invitation.account
    @inviter = invitation.invited_by

    mail(
      subject: "#{@inviter.name} heeft je uitgenodigd voor #{@account.name}",
      to: invitation.email
    )
  end

  # Voor WhatsApp/QR/Link flow (email verificatie)
  def verify_email(invitation)
    @invitation = invitation
    @account = invitation.account
    @verification_url = verify_invitation_email_url(
      @invitation.token,
      @invitation.email_verification_token
    )

    mail(
      subject: "Bevestig je email voor #{@account.name}",
      to: invitation.email
    )
  end
end

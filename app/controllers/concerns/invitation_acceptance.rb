module InvitationAcceptance
  extend ActiveSupport::Concern

  private
    # Returns :joined, :already_member, :unconfirmed or :refused.
    def join_invitation(user, invitation)
      return :unconfirmed if invitation.email_matches?(user) && !user.email_confirmed?

      already_member = invitation.account.active_users.exists?(user.id)
      return :refused unless invitation.accept!(user)

      user.update!(current_account: invitation.account)
      already_member ? :already_member : :joined
    end

    # For login and registration: the token was read from the session before it was
    # reset. Returns false when there was no invitation to handle, without redirecting.
    def redirect_for_pending_invitation(user, token, joined_prefix:)
      invitation = Invitation.find_by(token: token) if token.present?
      return false unless invitation

      account_name = invitation.account.name

      case join_invitation(user, invitation)
      when :unconfirmed
        session[:pending_invitation_token] = invitation.token
        redirect_to email_confirmation_pending_path, notice: "Bevestig eerst je e-mailadres. Daarna kun je meedoen met #{account_name}."
      when :joined
        redirect_to dashboard_path, notice: "#{joined_prefix} #{account_name}!"
      when :already_member
        redirect_to dashboard_path, notice: "Je bent al lid van #{account_name}."
      else
        redirect_to dashboard_path,
                    alert: "Deze uitnodiging kon niet worden geaccepteerd: ze is verlopen of bedoeld voor een ander emailadres."
      end
      true
    end

    # A link invitation's mail went to this address and the click came back to the browser that asked for it.
    # An admin naming an address, or a click in someone else's browser, proves nothing about this account.
    def apply_email_proof(user, proof)
      user.confirm_email! if proof.present? && proof == user.email_address
    end
end

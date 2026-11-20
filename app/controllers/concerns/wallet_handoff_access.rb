# A wallet's in-app browser has no login cookie. A redeemed handoff gives that browser a separate
# short-lived cookie, honoured only by actions that opt in here: linking a wallet. Every other
# controller still uses require_authentication, which never reads this cookie, so this cannot grow
# into a general session. Logging out destroys the session and with it the challenge row.
module WalletHandoffAccess
  extend ActiveSupport::Concern

  COOKIE = :wallet_handoff

  class_methods do
    def allow_wallet_handoff(only:)
      skip_before_action :require_authentication, only: only
      before_action :require_session_or_handoff, only: only
    end
  end

  private

  def require_session_or_handoff
    resume_session || resume_handoff || request_authentication
  end

  def resume_handoff
    id = cookies.encrypted[COOKIE]
    challenge = id && WalletChallenge.find_by(id: id, purpose: "handoff")
    return nil unless challenge&.handoff_grant_active?

    Current.session = challenge.session
  end

  def start_handoff_grant(challenge)
    cookies.encrypted[COOKIE] = {
      value: challenge.id, expires: WalletChallenge::HANDOFF_GRANT_LIFETIME.from_now,
      httponly: true, same_site: :lax, secure: Rails.env.production?
    }
  end
end

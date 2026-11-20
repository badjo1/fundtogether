# Issuing requires a real login, never a handoff: one handoff cannot mint the next.
class WalletHandoffsController < ChainApiController
  rate_limit to: 5, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create

  def create
    raise Chain::Refusal.new("email_not_confirmed", status: :forbidden) unless current_user.email_confirmed?

    challenge, token = WalletChallenge.issue_handoff!(user: current_user, session: Current.session)
    render json: { url: "#{WalletChallenge.origin}/wallet/handoff/#{token}", expires_at: challenge.expires_at.utc.iso8601 },
           status: :created
  end
end

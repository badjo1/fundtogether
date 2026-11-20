class WalletChallengesController < ChainApiController
  include WalletHandoffAccess

  allow_wallet_handoff only: :create
  rate_limit to: 10, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: :create

  def create
    raise Chain::Refusal.new("email_not_confirmed", status: :forbidden) unless current_user.email_confirmed?
    raise Chain::Refusal.new("invalid_purpose") unless params[:purpose].to_s == "link"

    address = Chain::WalletLinker.address!(params[:address])
    Chain::WalletLinker.refuse_contract!(address)
    challenge = WalletChallenge.issue_link!(user: current_user, session: Current.session, address: address,
                                            chain_id: Chain::Registry.default.chain_id)
    render json: { nonce: challenge.nonce, message: challenge.message, expires_at: challenge.expires_at.utc.iso8601 },
           status: :created
  end
end

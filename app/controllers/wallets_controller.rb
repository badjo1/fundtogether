class WalletsController < ChainApiController
  include WalletHandoffAccess

  allow_wallet_handoff only: :create
  rate_limit to: 10, within: 1.minute, by: -> { rate_limit_key }, with: -> { rate_limited }, only: [ :create, :destroy ]

  def index
    wallets = current_user.wallets.active.order(:id)
    render json: { wallets: wallets.map { |wallet| wallet_json(wallet) } }
  end

  def create
    wallet = Chain::WalletLinker.new(user: current_user)
                                .call(address: params[:address], nonce: params[:nonce], signature: params[:signature])
    render json: wallet_json(wallet), status: :created
  end

  # Unlinking changes nothing on-chain. The answer says so, because a compromised wallet stays
  # an owner until a swap_owner proposal executes.
  def destroy
    wallet = current_user.wallets.active.find_by(id: params[:id])
    return render_error("not_found", "Niet gevonden.", status: :not_found) unless wallet

    wallet.revoke!
    UserMailer.wallet_unlinked(current_user, wallet.address).deliver_later
    render json: wallet_json(wallet).merge(still_owner_of: wallet.still_owner_of)
  end

  private

  def wallet_json(wallet)
    { id: wallet.id, address: wallet.address, kind: wallet.kind, label: wallet.label,
      verified_at: wallet.verified_at.utc.iso8601, revoked_at: wallet.revoked_at&.utc&.iso8601 }
  end
end

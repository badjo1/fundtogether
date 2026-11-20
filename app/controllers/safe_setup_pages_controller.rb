# Step 3: choose ondertekenaars and goedkeuringen, then deploy from the admin's own wallet.
# Nothing here sends anything. The browser does, through safe-deploy and the JSON API.
class SafeSetupPagesController < FundPagesController
  def show
    return redirect_to account_transparency_path(@account) if @account.safe_active?

    @chains = Chain::Registry.enabled
    @chain = chosen_chain
    @candidates = candidates
    @linked_addresses = current_user.wallets.active.pluck(:address)
  end

  private

  def chosen_chain
    return @account.chain if @account.chain && params[:chain].blank?

    @chains.find { |chain| chain.chain_id.to_s == params[:chain].to_s } || @chains.first
  end

  # Members in join order with their wallet, so the page can show who still needs one.
  # A viewer can never sign, so they are not offered at all.
  def candidates
    memberships = @account.account_memberships.active.includes(user: :wallets).order(:id)
    memberships.reject(&:viewer?).map do |membership|
      wallet = membership.user.wallets.select(&:active?).min_by(&:id) if membership.user.email_confirmed?
      { user: membership.user, wallet: wallet }
    end
  end
end

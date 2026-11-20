# The wallets page. Linking runs in the browser through wallet-link and the JSON API, because the
# signature must come from the wallet. Unlinking and the QR are ordinary server actions.
class WalletPagesController < ApplicationController
  rate_limit to: 5, within: 1.minute, by: -> { current_user&.id || request.remote_ip },
             with: -> { redirect_to wallet_page_path, alert: "Te veel verzoeken. Probeer het over een minuut opnieuw." },
             only: :handoff
  rate_limit to: 10, within: 1.minute, by: -> { current_user&.id || request.remote_ip },
             with: -> { redirect_to wallet_page_path, alert: "Te veel verzoeken. Probeer het over een minuut opnieuw." },
             only: :unlink

  def show
    @wallets = current_user.wallets.active.order(:id)
    @chain = current_account&.chain
  end

  # Server-rendered QR. The token exists only in this response. Issuing needs a real login: a handoff
  # cannot mint the next one, because this controller never reads the handoff cookie.
  def handoff
    unless current_user.email_confirmed?
      return redirect_to(wallet_page_path, alert: Chain::Refusal::MESSAGES.fetch("email_not_confirmed"))
    end

    challenge, token = WalletChallenge.issue_handoff!(user: current_user, session: Current.session)
    @url = "#{WalletChallenge.origin}/wallet/handoff/#{token}"
    @expires_at = challenge.expires_at
    response.headers["Cache-Control"] = "no-store"
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to wallet_page_path, alert: "Vernieuw de pagina en probeer het opnieuw." }
    end
  end

  def ownership
    @wallet = current_user.wallets.active.find_by(id: params[:id])
    return head :not_found unless @wallet

    @funds = @wallet.still_owner_of
    render layout: false
  end

  # Always allowed: a compromised wallet must be removable from the account. It changes nothing on-chain.
  def unlink
    wallet = current_user.wallets.active.find_by(id: params[:id])
    return redirect_to(wallet_page_path, alert: "Deze wallet is niet gevonden.") unless wallet

    wallet.revoke!
    UserMailer.wallet_unlinked(current_user, wallet.address).deliver_later
    funds = wallet.still_owner_of
    if funds.any?
      names = funds.map { |fund| fund[:name] }.to_sentence(two_words_connector: " en ", last_word_connector: " en ")
      flash[:warning] = "Wallet ontkoppeld, maar op de blockchain blijft hij ondertekenaar van #{names}. " \
                        "Laat de groep hem vervangen met een voorstel."
    else
      flash[:notice] = "Wallet ontkoppeld."
    end
    redirect_to wallet_page_path
  end
end

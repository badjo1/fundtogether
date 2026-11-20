class BalancesController < ChainApiController
  before_action :set_fund
  before_action :require_active_safe

  def show
    render json: Chain::Balance.read(@account).merge(token: { address: @account.chain.token.address,
                                                              symbol: @account.chain.token.symbol,
                                                              decimals: @account.chain.token.decimals })
  end
end

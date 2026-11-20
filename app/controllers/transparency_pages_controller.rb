class TransparencyPagesController < FundPagesController
  def show
    @chain = @account.chain
  end
end

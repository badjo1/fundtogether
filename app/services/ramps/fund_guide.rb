module Ramps
  # What the ramp page may offer for one fund. Only routes for the fund's own chain and token, and
  # an honest state when there are none. Reads no chain data and makes no network call.
  class FundGuide
    def initialize(account)
      @account = account
    end

    # :no_chain, :chain_unavailable, :token_unsupported, :testnet or :mainnet
    def state
      return :no_chain unless @account.chain_id
      return :chain_unavailable unless chain
      return :token_unsupported unless guide && @account.token_address == chain.token.address

      chain.testnet? ? :testnet : :mainnet
    end

    def chain
      return @chain if defined?(@chain)

      @chain = Chain::Registry.enabled?(@account.chain_id) ? @account.chain : nil
    end

    def guide
      chain && Catalog.chain_guide(chain.key)
    end

    def usable?
      %i[testnet mainnet].include?(state)
    end

    def testnet?
      state == :testnet
    end

    def routes(direction)
      return [] unless state == :mainnet

      Catalog.routes(chain: chain.key, token: chain.token.symbol, direction: direction)
    end

    def route(id)
      return unless state == :mainnet

      Catalog.route(id, chain: chain.key, token: chain.token.symbol)
    end
  end
end

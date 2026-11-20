module Chain
  # The only reader of config/chains.yml. A chain that is not enabled does not exist as far
  # as callers can tell: mainnets stay unusable until FUNDTOGETHER_CHAINS names them.
  module Registry
    class ConfigError < StandardError; end
    class ChainDisabled < StandardError; end

    DEFAULT_CHAINS = "sepolia".freeze
    CONFIG_PATH = Rails.root.join("config/chains.yml")

    Token = Data.define(:symbol, :address, :decimals)
    Config = Data.define(:key, :chain_id, :name, :testnet, :native_symbol, :explorer_url, :confirmations,
                         :rpc_urls, :public_rpc_urls, :singleton, :factory, :fallback_handler, :token) do
      def testnet?
        testnet
      end

      # What a page may hand to the browser. rpc_urls can hold operator endpoints with keys from
      # FUNDTOGETHER_RPC_URLS_*, so it must never be rendered: only public_rpc_urls is.
      def browser_config
        { chain_id: chain_id, name: name, native_symbol: native_symbol, explorer_url: explorer_url,
          rpc_urls: public_rpc_urls, token: token.to_h }
      end
    end

    module_function

    def enabled
      enabled_keys.map { |key| all.fetch(key) }
    end

    def enabled?(chain_id)
      enabled.any? { |chain| chain.chain_id == chain_id }
    end

    # Raises for unknown and for known-but-disabled chains alike.
    def fetch(chain_id)
      enabled.find { |chain| chain.chain_id == chain_id } || raise(ChainDisabled, "chain #{chain_id.inspect} niet actief")
    end

    def default
      enabled.first
    end

    # The public endpoints from config/chains.yml, never the FUNDTOGETHER_RPC_URLS_* ones.
    def public_rpc_urls(chain_id)
      fetch(chain_id).public_rpc_urls
    end

    # For the CSP: origins only, and only of enabled chains' public endpoints.
    def public_rpc_origins
      enabled.flat_map(&:public_rpc_urls).map { |url| origin_of(url) }.uniq.sort
    end

    def origin_of(url)
      uri = URI.parse(url)
      "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
    end

    def enabled_keys
      keys = ENV.fetch("FUNDTOGETHER_CHAINS", "").split(",").map(&:strip).reject(&:empty?)
      keys = [ DEFAULT_CHAINS ] if keys.empty?
      unknown = keys - all.keys
      raise ConfigError, "Onbekende chains in FUNDTOGETHER_CHAINS: #{unknown.join(', ')}" if unknown.any?

      keys
    end

    def all
      @all ||= YAML.safe_load_file(CONFIG_PATH, aliases: true).fetch("chains").to_h { |key, raw| [ key, build(key, raw) ] }
    end

    def build(key, raw)
      Config.new(
        key: key, chain_id: raw.fetch("chain_id"), name: raw.fetch("name"), testnet: raw.fetch("testnet"),
        native_symbol: raw.fetch("native_symbol"), explorer_url: raw.fetch("explorer_url"),
        confirmations: raw.fetch("confirmations"), rpc_urls: rpc_urls(key, raw).freeze,
        public_rpc_urls: raw.fetch("rpc_urls").dup.freeze,
        singleton: raw.dig("safe", "singleton"), factory: raw.dig("safe", "factory"),
        fallback_handler: raw.dig("safe", "fallback_handler"),
        token: Token.new(**raw.fetch("token").symbolize_keys)
      )
    end
    private_class_method :build

    # Operators may put keyed endpoints in front through the environment. Never user input.
    def rpc_urls(key, raw)
      extra = ENV.fetch("FUNDTOGETHER_RPC_URLS_#{key.upcase}", "").split(",").map(&:strip).reject(&:empty?)
      urls = extra + raw.fetch("rpc_urls")
      urls.each { |url| raise ConfigError, "RPC-URL moet https zijn" unless url.start_with?("https://") }
      urls
    end
    private_class_method :rpc_urls
  end
end

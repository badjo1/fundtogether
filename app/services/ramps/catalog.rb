module Ramps
  # The only reader of config/ramps.yml. A disabled provider does not exist for callers of
  # routes and route: only all_routes (tests, link check) still sees it.
  module Catalog
    class ConfigError < StandardError; end

    CONFIG_PATH = Rails.root.join("config/ramps.yml")
    DIRECTIONS = %w[on off].freeze
    UNCONFIRMED_FEE_SENTENCE = "Controleer actuele kosten bij provider".freeze

    Source = Data.define(:label, :url)
    Route = Data.define(:id, :provider_key, :name, :kind, :direction, :chain, :token, :url, :regulator, :responsible,
                        :fee_status, :fees, :fee_source_url, :limits, :kyc, :currencies, :payment_methods,
                        :verification_status, :verification_note, :verified_on, :sources, :instructions, :warnings,
                        :legal_notice, :enable_env, :enabled_in_config) do
      def enabled?
        return ENV[enable_env] == "1" if enable_env

        enabled_in_config
      end

      def own_exchange?
        kind == "own_exchange"
      end

      def fee_confirmed?
        fee_status == "confirmed"
      end
    end
    Faucet = Data.define(:name, :url, :token, :network, :limits, :verified_on, :sources)
    Gas = Data.define(:token, :rough_need, :where, :verified_on, :sources)
    ChainGuide = Data.define(:key, :network_label, :route_note, :gas, :faucet)

    module_function

    def routes(chain:, token:, direction:)
      all_routes.select do |route|
        route.enabled? && route.chain == chain && route.token == token && route.direction == direction
      end
    end

    def route(id, chain:, token:)
      all_routes.find { |route| route.id == id && route.enabled? && route.chain == chain && route.token == token }
    end

    def chain_guide(key)
      chain_guides[key]
    end

    def all_routes
      @all_routes ||= config.fetch("routes").map { |raw| build_route(raw) }.freeze
    end

    def chain_guides
      @chain_guides ||= config.fetch("chains").to_h { |key, raw| [ key, build_guide(key, raw) ] }.freeze
    end

    # Every external URL in the file, for the manual link check.
    def all_urls
      route_urls = all_routes.flat_map { |route| [ route.url, route.fee_source_url, *route.sources.map(&:url) ] }
      guide_urls = chain_guides.values.flat_map do |guide|
        [ guide.faucet&.url, *guide.faucet&.sources&.map(&:url), *guide.gas.sources.map(&:url) ]
      end
      (route_urls + guide_urls).compact.uniq
    end

    def config
      @config ||= YAML.safe_load_file(CONFIG_PATH, aliases: true, permitted_classes: [ Date ])
    end
    private_class_method :config

    def build_route(raw)
      provider_key = raw.fetch("provider")
      provider = config.fetch("providers").fetch(provider_key)
      merged = provider.merge(raw)
      Route.new(
        id: raw.fetch("id"), provider_key: provider_key, name: provider.fetch("name"), kind: provider.fetch("kind"),
        direction: direction(raw), chain: raw.fetch("chain"), token: raw.fetch("token"), url: https(merged["url"]),
        regulator: merged.fetch("regulator"), responsible: merged.fetch("responsible"),
        fee_status: merged.fetch("fee_status"), fees: merged.fetch("fees"), fee_source_url: https(merged["fee_source_url"]),
        limits: merged.fetch("limits"), kyc: merged.fetch("kyc"), currencies: merged.fetch("currencies"),
        payment_methods: merged.fetch("payment_methods"), verification_status: merged.fetch("verification_status"),
        verification_note: merged["verification_note"], verified_on: merged.fetch("verified_on"),
        sources: build_sources(merged.fetch("sources")), instructions: merged.fetch("instructions").freeze,
        warnings: merged.fetch("warnings", []).freeze, legal_notice: merged["legal_notice"],
        enable_env: merged["enable_env"], enabled_in_config: merged.fetch("enabled")
      )
    end
    private_class_method :build_route

    def build_guide(key, raw)
      gas = raw.fetch("gas")
      faucet = raw["faucet"]
      ChainGuide.new(
        key: key, network_label: raw.fetch("network_label"), route_note: raw["route_note"],
        gas: Gas.new(token: gas.fetch("token"), rough_need: gas.fetch("rough_need"), where: gas.fetch("where").freeze,
                     verified_on: gas.fetch("verified_on"), sources: build_sources(gas.fetch("sources"))),
        faucet: faucet && Faucet.new(name: faucet.fetch("name"), url: https(faucet.fetch("url")), token: faucet.fetch("token"),
                                     network: faucet.fetch("network"), limits: faucet.fetch("limits"),
                                     verified_on: faucet.fetch("verified_on"), sources: build_sources(faucet.fetch("sources")))
      )
    end
    private_class_method :build_guide

    def build_sources(list)
      list.map { |source| Source.new(label: source.fetch("label"), url: https(source.fetch("url"))) }.freeze
    end
    private_class_method :build_sources

    def direction(raw)
      value = raw.fetch("direction")
      raise ConfigError, "Onbekende richting: #{value}" unless DIRECTIONS.include?(value)

      value
    end
    private_class_method :direction

    def https(url)
      raise ConfigError, "Ramp-URL moet https zijn: #{url}" if url && !url.start_with?("https://")

      url
    end
    private_class_method :https
  end
end

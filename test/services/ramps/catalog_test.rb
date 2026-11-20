require "test_helper"

class RampsCatalogTest < ActiveSupport::TestCase
  FLAG = "FUNDTOGETHER_ENABLE_MTPELERIN".freeze
  FREE_WORDS = /\b(gratis|free|kosteloos|zonder kosten|geen kosten)\b/i

  def with_flag(value)
    previous = ENV[FLAG]
    ENV[FLAG] = value
    yield
  ensure
    ENV[FLAG] = previous
  end

  def routes
    Ramps::Catalog.all_routes
  end

  def query_of(route)
    URI.decode_www_form(URI.parse(route.url).query).to_h
  end

  test "unconfirmed fees never claim to be free and send people to the provider" do
    unconfirmed = routes.reject(&:fee_confirmed?)
    assert_not_empty unconfirmed
    unconfirmed.each do |route|
      assert_no_match FREE_WORDS, route.fees, route.id
      assert_includes route.fees, Ramps::Catalog::UNCONFIRMED_FEE_SENTENCE, route.id
    end
  end

  test "monerium fees are unconfirmed, as researched" do
    monerium = routes.select { |route| route.provider_key == "monerium" }
    assert_equal 2, monerium.size
    assert monerium.none?(&:fee_confirmed?)
  end

  test "fee_status has only known values" do
    assert_equal %w[confirmed unconfirmed], routes.map(&:fee_status).uniq.sort
  end

  test "every entry has a source, a date and every disclosure field" do
    routes.each do |route|
      assert_not_empty route.sources, route.id
      route.sources.each { |source| assert source.label.present? && source.url.start_with?("https://"), route.id }
      assert_kind_of Date, route.verified_on, route.id
      assert route.fee_source_url.present?, route.id if route.fee_confirmed?
      %i[name direction fees limits kyc currencies payment_methods regulator responsible].each do |field|
        assert route.public_send(field).present?, "#{route.id} mist #{field}"
      end
      assert_includes RampsHelper::VERIFICATION_LABELS.keys, route.verification_status, route.id
      assert_not_empty route.instructions, route.id
    end
  end

  test "every chain guide has sourced gas information, and testnets a sourced faucet" do
    Chain::Registry.all.each_value do |chain|
      guide = Ramps::Catalog.chain_guide(chain.key)
      assert guide, "geen gids voor #{chain.key}"
      assert_not_empty guide.gas.sources, chain.key
      assert_kind_of Date, guide.gas.verified_on
      if chain.testnet?
        assert_not_empty guide.faucet.sources
        assert_kind_of Date, guide.faucet.verified_on
      else
        assert_nil guide.faucet
      end
    end
  end

  test "routes exist only for a real chain and that chain's own token" do
    routes.each do |route|
      chain = Chain::Registry.all.fetch(route.chain)
      assert_equal chain.token.symbol, route.token, route.id
      assert_not chain.testnet?, "#{route.id}: echte providers horen niet bij een testnet"
    end
  end

  test "providers link out, exchanges only give instructions" do
    routes.each do |route|
      if route.own_exchange?
        assert_nil route.url, route.id
      else
        assert route.url.start_with?("https://"), route.id
      end
    end
  end

  test "the file holds no on-chain address, so no deposit address can reach a proposal" do
    assert_no_match(/0x[0-9a-fA-F]{20,}/, Ramps::Catalog::CONFIG_PATH.read)
  end

  test "no revenue-share parameter, signature or personal data in any URL" do
    forbidden = %w[rfr ref referrer referral partner affiliate fee addr code hash email phone name signature]
    routes.select(&:url).each do |route|
      next unless URI.parse(route.url).query

      assert_empty query_of(route).keys & forbidden, route.id
    end
  end

  test "mt pelerin links use the researched network and token" do
    buy = routes.find { |route| route.id == "base_eurc_mtpelerin_on" }
    sell = routes.find { |route| route.id == "base_eurc_mtpelerin_off" }

    assert_equal({ "tab" => "buy", "net" => "base_mainnet", "dnet" => "base_mainnet", "bdc" => "EURC", "type" => "direct-link" },
                 query_of(buy).slice("tab", "net", "dnet", "bdc", "type"))
    assert_equal({ "tab" => "sell", "net" => "base_mainnet", "snet" => "base_mainnet", "ssc" => "EURC", "type" => "direct-link" },
                 query_of(sell).slice("tab", "net", "snet", "ssc", "type"))
    assert_equal "widget.mtpelerin.com", URI.parse(buy.url).host
  end

  test "mt pelerin needs exactly the flag, and states its legal status when on" do
    { nil => false, "" => false, "0" => false, "true" => false, "1" => true }.each do |value, expected|
      with_flag(value) do
        found = Ramps::Catalog.routes(chain: "base", token: "EURC", direction: "on").any? { |route| route.provider_key == "mt_pelerin" }
        assert_equal expected, found, "vlag #{value.inspect}"
        assert_equal expected, Ramps::Catalog.route("base_eurc_mtpelerin_on", chain: "base", token: "EURC").present?
      end
    end

    routes.select { |route| route.provider_key == "mt_pelerin" }.each do |route|
      assert_match(/MiCA/, route.legal_notice)
      assert_match(/ESMA/, route.legal_notice)
    end
  end

  test "mt pelerin discloses its bracket, hold and limits" do
    route = routes.find { |entry| entry.id == "base_eurc_mtpelerin_on" }
    assert_match(/0-500/, route.fees)
    assert_match(/hele bedrag/, route.fees)
    assert_match(/CHF 20/, route.fees)
    assert_match(/7 dagen/, route.kyc)
    assert_match(/CHF 999/, route.kyc)
  end

  test "lookups never cross chain or token" do
    assert_nil Ramps::Catalog.route("gnosis_eure_monerium_on", chain: "base", token: "EURC")
    assert_nil Ramps::Catalog.route("gnosis_eure_monerium_on", chain: "gnosis", token: "EURC")
    assert_nil Ramps::Catalog.route("does_not_exist", chain: "gnosis", token: "EURe")
    assert_empty Ramps::Catalog.routes(chain: "sepolia", token: "EURC", direction: "on")
  end

  test "all_urls is https and includes routes, sources, gas and faucet" do
    urls = Ramps::Catalog.all_urls
    assert urls.all? { |url| url.start_with?("https://") }
    assert_includes urls, "https://monerium.app/"
    assert_includes urls, "https://faucet.circle.com/"
    assert_includes urls, "https://docs.gnosischain.com/tools/Faucets"
    assert(urls.any? { |url| url.include?("widget.mtpelerin.com") })
  end

  test "ramp views embed nothing" do
    Rails.root.glob("app/views/ramps/*").each do |file|
      assert_no_match(/<iframe|<embed|<object|<script/i, file.read, file.to_s)
    end
  end
end

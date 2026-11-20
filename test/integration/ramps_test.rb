require "test_helper"

class RampsTest < ActionDispatch::IntegrationTest
  FLAG = "FUNDTOGETHER_ENABLE_MTPELERIN".freeze
  OWN_WALLET = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf".freeze
  OTHER_WALLET = "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf".freeze
  SAFE = "0x1111111111111111111111111111111111111111".freeze
  FREE_WORDS = /\b(gratis|free)\b/i

  setup do
    @previous_env = ENV.to_h.slice("FUNDTOGETHER_CHAINS", FLAG)
    ENV["FUNDTOGETHER_CHAINS"] = "sepolia,base,gnosis"
    ENV.delete(FLAG)

    @fund = accounts(:one)
    @admin = users(:one)
    @member = users(:two)
    @admin.update!(current_account: @fund)
    @member.update!(current_account: @fund)
    @viewer = add_to_fund(create_user("viewer"), @fund, role: "viewer")
  end

  teardown do
    ENV.delete("FUNDTOGETHER_CHAINS")
    ENV.delete(FLAG)
    @previous_env.each { |key, value| ENV[key] = value }
  end

  def put_fund_on(key, status: "active")
    chain = Chain::Registry.all.fetch(key)
    @fund.update!(chain_id: chain.chain_id, token_address: chain.token.address, safe_address: SAFE, safe_salt_nonce: 1,
                  safe_status: status, safe_owners: [ OWN_WALLET, OTHER_WALLET ], safe_threshold: 2)
  end

  def external_links
    css_select("a").select { |link| link["href"].to_s.match?(%r{\Ahttps?://|\A//}) }
  end

  def assert_external_links_are_safe
    links = external_links
    assert_not_empty links
    links.each do |link|
      assert_equal "_blank", link["target"], link["href"]
      assert_equal %w[noopener noreferrer], link["rel"].split.sort, link["href"]
    end
  end

  def action_links
    css_select("[data-ramp-action]")
  end

  # Access
  test "logged out people go to the login page" do
    get account_ramp_path(@fund)
    assert_redirected_to new_session_path
  end

  test "non-members and inactive members get the same 404 as a missing fund" do
    inactive = add_to_fund(create_user("inactive"), @fund, active: false)
    [ create_user("outsider"), inactive ].each do |user|
      sign_in_as user
      get account_ramp_path(@fund)
      assert_response :not_found
      existing = response.body
      get account_ramp_path(0)
      assert_response :not_found
      assert_equal existing, response.body
      get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
      assert_response :not_found
    end
  end

  test "access follows the requested fund, not the fund selected in the sidebar" do
    @member.update!(current_account: accounts(:two))
    sign_in_as @member
    get account_ramp_path(accounts(:two))
    assert_response :not_found
  end

  test "a viewer can read everything but gets no actions" do
    put_fund_on("gnosis")
    link_wallet(@viewer, OWN_WALLET)
    sign_in_as @viewer

    [ account_ramp_path(@fund), account_ramp_path(@fund, direction: "off") ].each do |path|
      get path
      assert_response :success
      assert_select "[data-ramp-disclosure]"
      assert_select "[data-ramp-route=?]", path.include?("off") ? "gnosis_eure_monerium_off" : "gnosis_eure_monerium_on"
      assert_empty action_links, path
      assert_select "[data-ramp-wallet]", 0
      assert_includes response.body, "leesrechten"
    end

    get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
    assert_redirected_to dashboard_path
    assert_equal "Met alleen leesrechten kun je dit niet doen.", flash[:alert]
  end

  test "a viewer gets no faucet action on a testnet" do
    put_fund_on("sepolia")
    sign_in_as @viewer
    get account_ramp_path(@fund)
    assert_empty action_links
  end

  test "members and admins get the actions" do
    put_fund_on("gnosis")
    [ @member, @admin ].each do |user|
      sign_in_as user
      get account_ramp_path(@fund)
      assert_select "[data-ramp-action=leave]", 1
      get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
      assert_response :success
    end
  end

  # Routes per chain
  test "gnosis with EURe offers Monerium and says why there is no exchange route" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "[data-ramp-network]", /Gnosis/
    assert_select "[data-ramp-route]", 1
    assert_select "[data-ramp-route=gnosis_eure_monerium_on]"
    assert_includes response.body, "xDAI"
    assert_includes response.body, "Bitvavo"
    assert_no_match(/Mt Pelerin|Mtpelerin/i, css_select("[data-ramp-route], [data-ramp-disclosure-entry]").text)
  end

  test "base with EURC has no Monerium route, and Mt Pelerin stays hidden without the flag" do
    put_fund_on("base")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "[data-ramp-route]", 1
    assert_select "[data-ramp-route=base_eurc_exchange_on]"
    assert_no_match(/widget\.mtpelerin/, response.body)
    assert_select "[data-ramp-route] h4", text: /Monerium/, count: 0
    assert_select "[data-ramp-route] h4", text: /Mt Pelerin/, count: 0

    get leave_account_ramp_path(@fund, route: "base_eurc_mtpelerin_on")
    assert_response :not_found
  end

  test "base with the flag shows Mt Pelerin with its legal status" do
    ENV[FLAG] = "1"
    put_fund_on("base")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "[data-ramp-route=base_eurc_mtpelerin_on]", /MiCA/
    assert_select "[data-ramp-disclosure-entry=base_eurc_mtpelerin_on]", /ESMA/
    assert_select "[data-ramp-disclosure-entry=base_eurc_mtpelerin_on]", /CHF 999/
    assert_select "[data-ramp-disclosure-entry=base_eurc_mtpelerin_on]", /7 dagen/

    get leave_account_ramp_path(@fund, route: "base_eurc_mtpelerin_on")
    assert_response :success
    assert_select "[data-ramp-disclosure-entry]", /MiCA/
    assert_select "[data-ramp-interstitial]", /MiCA/
    assert_select "a[data-ramp-action=external][href*=?]", "widget.mtpelerin.com"
  end

  test "exchange route warns about the exact network and lost funds, and links no exchange" do
    put_fund_on("base")
    sign_in_as @member
    get account_ramp_path(@fund)

    card = css_select("[data-ramp-route=base_eurc_exchange_on]")
    assert_match(/precies Base/, card.text)
    assert_match(/geld kwijtraken/, card.text)
    assert_match(/alleen op Ethereum/, card.text)
    assert_select "[data-ramp-route=base_eurc_exchange_on] a", 0
  end

  test "a route of another chain cannot be opened on this fund" do
    put_fund_on("base")
    sign_in_as @member
    get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
    assert_response :not_found
    get leave_account_ramp_path(@fund, route: "https://example.com")
    assert_response :not_found
    get leave_account_ramp_path(@fund)
    assert_response :not_found
  end

  test "an instructions-only route has no interstitial" do
    put_fund_on("base")
    sign_in_as @member
    get leave_account_ramp_path(@fund, route: "base_eurc_exchange_on")
    assert_response :not_found
  end

  # Testnet and empty states
  test "a testnet fund says real ramps do not apply and explains the faucet" do
    ENV[FLAG] = "1"
    put_fund_on("sepolia")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_response :success
    assert_includes response.body, "testgeld zonder waarde"
    assert_includes response.body, "Ethereum Sepolia"
    assert_includes response.body, "Echte providers"
    assert_select "a[data-ramp-action=faucet][href=?]", "https://faucet.circle.com/"
    assert_select "[data-ramp-route]", 0
    assert_no_match(/monerium\.app|widget\.mtpelerin/, response.body)
    assert_external_links_are_safe

    get leave_account_ramp_path(@fund, route: "base_eurc_mtpelerin_on")
    assert_response :not_found

    get account_ramp_path(@fund, direction: "off")
    assert_select "[data-ramp-no-fiat]"
  end

  test "a fund without a chain gets an honest empty state" do
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_response :success
    assert_select "[data-ramp-empty=no_chain]"
    assert_select "[data-ramp-stepper]", 0
  end

  test "a fund on a chain that is not enabled gets an honest empty state, not an error" do
    put_fund_on("gnosis")
    ENV["FUNDTOGETHER_CHAINS"] = "sepolia"
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_response :success
    assert_select "[data-ramp-empty=chain_unavailable]"
    get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
    assert_response :not_found
  end

  test "a fund with an unknown token gets no routes" do
    @fund.update!(chain_id: 8453, token_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "[data-ramp-empty=token_unsupported]"
    assert_select "[data-ramp-route]", 0
  end

  # On-ramp
  test "the on-ramp stepper has its four steps in order" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund)

    titles = css_select("[data-ramp-stepper=on] [data-ramp-step] h3").map(&:text)
    assert_equal 4, titles.size
    assert_match(/wallet/, titles[0])
    assert_match(/provider/, titles[1])
    assert_match(/gas/, titles[2])
    assert_match(/Draag bij/, titles[3])
  end

  test "step one shows only this person's active wallets" do
    put_fund_on("gnosis")
    link_wallet(@member, OWN_WALLET)
    link_wallet(@admin, OTHER_WALLET)
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "[data-ramp-wallet]", 1
    assert_select "[data-ramp-wallet] code", Chain::Address.checksum(OWN_WALLET)
    assert_not_includes response.body.downcase, OTHER_WALLET

    @member.wallets.first.revoke!
    get account_ramp_path(@fund)
    assert_select "[data-ramp-wallet]", 0
    assert_includes response.body, "nog geen wallet"
  end

  test "the page never shows the fund's Safe address" do
    put_fund_on("gnosis")
    sign_in_as @member
    [ account_ramp_path(@fund), account_ramp_path(@fund, direction: "off"),
      leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on") ].each do |path|
      get path
      assert_not_includes response.body.downcase, SAFE
    end
  end

  test "step four links to the contribute page once the Safe is active" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund)
    assert_select "a[data-ramp-action=contribute][href=?]", account_contribute_path(@fund)
  end

  test "a fund without an active Safe warns against sending money" do
    put_fund_on("gnosis", status: "deploying")
    link_wallet(@member, OWN_WALLET)
    sign_in_as @member
    get account_ramp_path(@fund)
    assert_includes response.body, "Stuur nog geen geld"
    assert_select "[data-ramp-action=contribute]", 0

    get account_ramp_path(@fund, direction: "off")
    assert_select "[data-ramp-action=payout]", 0
  end

  # Interstitial and links
  test "providers are reached only through the interstitial" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_select "a[href=?]", "https://monerium.app/", 0
    assert_select "a[data-ramp-action=leave][href=?]", leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")

    get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")
    assert_select "h2", "Je verlaat FundTogether"
    text = css_select("[data-ramp-interstitial]").text
    assert_match(/identiteitscontrole en het geld/, text)
    assert_match(/houdt niets vast en neemt geen vergoeding/, text)
    assert_match(/niet met echt geld getest/, text)
    assert_select "a[data-ramp-action=external][href=?]", "https://monerium.app/"
  end

  test "every external link opens a new tab with noopener noreferrer" do
    put_fund_on("gnosis")
    link_wallet(@member, OWN_WALLET)
    sign_in_as @member
    [ account_ramp_path(@fund), account_ramp_path(@fund, direction: "off"),
      leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on") ].each do |path|
      get path
      assert_response :success
      assert_external_links_are_safe
      assert_select "iframe", 0
    end
  end

  test "the provider link carries no personal data" do
    put_fund_on("gnosis")
    link_wallet(@member, OWN_WALLET)
    sign_in_as @member
    get leave_account_ramp_path(@fund, route: "gnosis_eure_monerium_on")

    href = css_select("a[data-ramp-action=external]").first["href"]
    assert_equal "https://monerium.app/", href
  end

  test "the page runs under the strict policy with no inline style or script" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund)

    assert_match(/script-src 'self' 'nonce-/, response.headers["Content-Security-Policy"])
    assert_select "[style]", 0
    assert_select "style", 0
    assert_select "[onclick]", 0
  end

  # Disclosures
  test "the standing block names fees, currency, limits, KYC, responsibility and date" do
    put_fund_on("gnosis")
    sign_in_as @viewer
    get account_ramp_path(@fund)

    entry = css_select("[data-ramp-disclosure-entry=gnosis_eure_monerium_on]").text
    %w[Kosten Valuta Betaalmethoden Limieten Identiteitscontrole Toezicht].each { |label| assert_includes entry, label }
    assert_includes entry, "Wie is verantwoordelijk"
    assert_includes entry, "08-11-2026"
    assert_includes entry, Ramps::Catalog::UNCONFIRMED_FEE_SENTENCE
    assert_includes entry, "Central Bank of Iceland"
    assert_select "[data-ramp-disclosure-entry=gnosis_eure_monerium_on] a[data-ramp-source]"
    assert_select "[data-ramp-promise]", /niet|Geen van deze routes/
    assert_includes css_select("[data-ramp-promise]").text, "met echt geld getest"
  end

  test "pages with only unconfirmed fees never say free" do
    { "gnosis" => %w[on off], "base" => %w[on off] }.each do |key, directions|
      put_fund_on(key)
      sign_in_as @member
      directions.each do |direction|
        get account_ramp_path(@fund, direction: direction)
        assert_response :success
        assert_no_match FREE_WORDS, css_select("main").text, "#{key} #{direction}"
      end
      @fund.update_columns(safe_status: "draft", chain_id: nil, token_address: nil, safe_address: nil)
    end
  end

  # Off-ramp
  test "the off-ramp proposes a payout to the member's own wallet only" do
    put_fund_on("gnosis")
    link_wallet(@member, OWN_WALLET)
    link_wallet(@admin, OTHER_WALLET)
    sign_in_as @member
    get account_ramp_path(@fund, direction: "off")

    titles = css_select("[data-ramp-stepper=off] [data-ramp-step] h3").map(&:text)
    assert_match(/eigen wallet/, titles[0])
    assert_match(/goedkeuring/, titles[1])
    assert_match(/gas/, titles[2])
    assert_match(/provider/, titles[3])

    link = css_select("a[data-ramp-action=payout]")
    assert_equal 1, link.size
    assert_select "[data-ramp-wallet] code", Chain::Address.checksum(OWN_WALLET)
    assert_not_includes response.body.downcase, OTHER_WALLET.delete_prefix("0x")

    uri = URI.parse(link.first["href"])
    assert_equal new_account_proposal_page_path(@fund), uri.path
    assert_equal({ "kind" => "transfer_token", "recipient" => OWN_WALLET }, Rack::Utils.parse_query(uri.query))
  end

  test "no wallet means no payout action" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund, direction: "off")
    assert_select "[data-ramp-action=payout]", 0
    assert_includes response.body, "nog geen wallet"
    assert_select "a[data-ramp-action=link_wallet][href=?]", wallet_page_path
  end

  test "the off-ramp explains approvals and who receives the euros, as non-advice" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund, direction: "off")

    assert_select "[data-ramp-threshold]", /2 van de 2/
    fiat = css_select("[data-ramp-fiat]").text
    assert_match(/De ontvanger, niet het fonds/, fiat)
    assert_match(/belasting en administratie/, fiat)
    assert_match(/geen belasting- of juridisch advies/, fiat)
  end

  test "the off-ramp warns against a provider deposit address in a proposal" do
    put_fund_on("base")
    link_wallet(@member, OWN_WALLET)
    sign_in_as @member
    get account_ramp_path(@fund, direction: "off")

    assert_includes response.body, "Zet nooit een stortingsadres van een provider in een voorstel"
    assert_select "[data-ramp-route=base_eurc_exchange_off]", /nooit rechtstreeks vanuit de Safe/
    assert_select "[data-ramp-route=base_eurc_circle_off]"
  end

  test "a direction value outside the list falls back to the on-ramp" do
    put_fund_on("gnosis")
    sign_in_as @member
    get account_ramp_path(@fund, direction: "<script>")
    assert_response :success
    assert_select "[data-ramp-stepper=on]"
  end
end

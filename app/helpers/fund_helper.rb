module FundHelper
  MONTHS = %w[jan feb mrt apr mei jun jul aug sep okt nov dec].freeze
  SAFE_WALLET_PREFIX = { 11_155_111 => "sep", 8453 => "base", 100 => "gno" }.freeze
  KIND_LABELS = { "transfer_token" => "Uitbetaling", "transfer_native" => "Uitbetaling (netwerkmunt)",
                  "add_owner" => "Ondertekenaar toevoegen", "remove_owner" => "Ondertekenaar verwijderen",
                  "swap_owner" => "Ondertekenaar vervangen", "change_threshold" => "Aantal goedkeuringen wijzigen",
                  "rejection" => "Afwijzing" }.freeze
  BUCKET_LABELS = { "needs_me" => "Wacht op jou", "ready" => "Klaar om uit te voeren", "waiting" => "Wacht op anderen",
                    "insufficient" => "Te weinig saldo", "stale" => "Verouderd", "executed" => "Uitgevoerd", "failed" => "Mislukt",
                    "superseded" => "Vervallen", "cancelled" => "Ingetrokken", "unknown" => "Status onbekend" }.freeze
  BUCKET_CLASSES = { "needs_me" => "bg-blue-100 text-blue-800", "ready" => "bg-green-100 text-green-800",
                     "waiting" => "bg-yellow-100 text-yellow-800", "insufficient" => "bg-red-100 text-red-800", "stale" => "bg-gray-100 text-gray-800",
                     "executed" => "bg-green-100 text-green-800", "failed" => "bg-red-100 text-red-800",
                     "superseded" => "bg-gray-100 text-gray-800", "cancelled" => "bg-gray-100 text-gray-800", "unknown" => "bg-gray-100 text-gray-800" }.freeze
  REASON_TEXT = { "not_open" => "Dit voorstel staat niet meer open.",
                  "tampered" => "De opgeslagen gegevens kloppen niet met de hash. Niet ondertekenen en meld dit aan je medeleden.",
                  "nonce_passed" => "De Safe is al verder dan dit voorstel. Het kan niet meer worden uitgevoerd.",
                  "waiting_for_earlier_nonce" => "Eerst moet een eerder voorstel worden uitgevoerd of afgewezen.",
                  "calldata_stale" => "De ondertekenaars zijn veranderd sinds dit voorstel is gemaakt. Maak een nieuw voorstel.",
                  "not_enough_signatures" => "Er zijn nog niet genoeg goedkeuringen van huidige ondertekenaars.",
                  "balance_unknown" => "Het saldo van de Safe kon nu niet worden gelezen, dus we weten niet of dit zou lukken. Probeer het zo opnieuw." }.freeze
  # The fragment of a wallet status list, for data-show-wallet.
  WALLET_BUSY = "requesting_accounts switching_chain adding_chain awaiting_signature submitting".freeze

  def pluralize_nl(count, one, many)
    "#{count} #{count == 1 ? one : many}"
  end

  # The fund's chain, or nil when it has none yet or the operator switched it off. Never raises in a view.
  def fund_chain(account)
    account&.chain
  rescue Chain::Registry::ChainDisabled
    nil
  end

  # What a draft fund will run on is also honest to show: with only a testnet enabled, it is test money.
  def testnet_fund?(account)
    return false unless account

    chain = fund_chain(account) || (account.chain_id ? nil : Chain::Registry.default)
    chain&.testnet? || false
  end

  def money(units, token)
    "#{Chain::Amount.format(units, token.decimals)} #{token.symbol}"
  end

  def native_money(units, chain)
    "#{Chain::Amount.format(units, 18)} #{chain.native_symbol}"
  end

  def checksum_address(address)
    address.present? ? Chain::Address.checksum(address) : ""
  end

  def short_address(address)
    full = checksum_address(address)
    full.length > 12 ? "#{full[0, 6]}…#{full[-4..]}" : full
  end

  def explorer_tx_url(chain, tx_hash)
    "#{chain.explorer_url}/tx/#{tx_hash}"
  end

  def explorer_address_url(chain, address)
    "#{chain.explorer_url}/address/#{checksum_address(address)}"
  end

  # Safe{Wallet} addresses a Safe as <chain prefix>:<address>.
  def safe_wallet_url(chain, address)
    prefix = SAFE_WALLET_PREFIX[chain.chain_id]
    prefix && "https://app.safe.global/home?safe=#{prefix}:#{checksum_address(address)}"
  end

  def threshold_sentence(threshold, owner_count)
    return "#{threshold} ondertekenaar moet goedkeuren" if owner_count == 1 && threshold == 1

    "#{threshold} van de #{owner_count} moeten goedkeuren"
  end

  def nl_time(time)
    time&.in_time_zone("Amsterdam")
  end

  def nl_date(time)
    local = nl_time(time)
    local && "#{local.day} #{MONTHS[local.month - 1]} #{local.year}"
  end

  def nl_datetime(time)
    local = nl_time(time)
    local && "#{nl_date(time)}, #{local.strftime('%H:%M')}"
  end

  def clock_time(time)
    nl_time(time)&.strftime("%H:%M:%S")
  end

  # rqrcode writes attributes only, no style=, so the strict CSP stays intact. Escaped by the library.
  def qr_svg(text, css_class: "w-48 h-48")
    RQRCode::QRCode.new(text).as_svg(color: "000", shape_rendering: "crispEdges", module_size: 4, standalone: true,
                                     use_path: true, viewbox: true, svg_attributes: { class: css_class, role: "img",
                                                                                     "aria-label": "QR-code" }).html_safe
  end

  def kind_label(kind)
    KIND_LABELS.fetch(kind, kind.to_s.humanize)
  end

  def bucket_label(bucket)
    BUCKET_LABELS.fetch(bucket)
  end

  def bucket_class(bucket)
    BUCKET_CLASSES.fetch(bucket)
  end

  def reason_text(reason)
    REASON_TEXT[reason]
  end

  # Maps addresses to who holds them now. Name only for an active wallet of a member of this fund.
  def member_name_for(account, address)
    @member_names ||= {}
    @member_names[address] ||= begin
      wallet = Wallet.active.includes(:user).find_by(address: address)
      wallet && account.account_memberships.active.exists?(user_id: wallet.user_id) ? wallet.user.display_name : nil
    end
  end

  # One line about what a proposal does. Server-side and for lists only: signing screens show the
  # values the browser computed itself.
  def proposal_summary(account, proposal, chain)
    params = proposal.params
    case proposal.kind
    when "transfer_token" then "#{money(params['amount'], chain.token)} naar #{recipient_label(account, params['recipient'])}"
    when "transfer_native" then "#{native_money(params['amount'], chain)} naar #{recipient_label(account, params['recipient'])}"
    when "add_owner" then "#{recipient_label(account, params['owner'])} toevoegen, daarna #{params['threshold']} goedkeuringen nodig"
    when "remove_owner" then "#{recipient_label(account, params['owner'])} verwijderen, daarna #{params['threshold']} goedkeuringen nodig"
    when "swap_owner" then "#{recipient_label(account, params['old_owner'])} vervangen door #{recipient_label(account, params['new_owner'])}"
    when "change_threshold" then "Voortaan #{params['threshold']} goedkeuringen nodig"
    when "rejection" then "Wijst alle voorstellen met volgnummer #{params['nonce']} af. Verplaatst geen geld."
    end
  end

  # A name alone is not enough where money or signers are concerned: two members can share one.
  def recipient_label(account, address)
    name = member_name_for(account, address)
    name ? "#{name} (#{short_address(address)})" : short_address(address)
  end

  # What an executed proposal paid, for the activity list: a native transfer emits no event of its own, so this
  # comes from the proposal whose hash the chain reported, and says so. Without a proposal we do not know.
  def execution_payout(event, chain)
    proposal = event.safe_proposal
    return { known: false, note: "Buiten FundTogether uitgevoerd. Bekijk de transactie voor het bedrag en de ontvanger." } unless proposal

    case proposal.kind
    when "transfer_native" then { known: true, amount: native_money(proposal.params["amount"], chain), recipient: proposal.params["recipient"] }
    when "transfer_token" then { known: true, amount: money(proposal.params["amount"], chain.token), recipient: proposal.params["recipient"] }
    end
  end

  # Same first and last four hex characters as a member's wallet: the shape of an address poisoning attempt.
  def lookalike_of(account, address)
    @known_wallets ||= {}
    known = @known_wallets[account.id] ||= Wallet.active.where(user_id: account.active_users.select(:id)).includes(:user).to_a
    shape = ->(value) { [ value[2, 4], value[-4..] ] }
    known.find { |wallet| wallet.address != address && shape.call(wallet.address) == shape.call(address) }&.user&.display_name
  end

  # Sidebar entry. Full class strings: the Tailwind scanner cannot see interpolated ones.
  def nav_item(label, path, icon_name, active: current_page?(path))
    classes = "flex items-center space-x-3 w-full px-4 py-2.5 rounded-lg text-left transition-all duration-200 "
    classes += active ? "bg-blue-600 text-white shadow-lg" : "text-gray-300 hover:bg-gray-800 hover:text-white"
    link_to path, class: classes, "aria-current": (active ? "page" : nil) do
      safe_join([ icon(icon_name, class: "w-5 h-5 flex-shrink-0"), content_tag(:span, label, class: "font-medium") ])
    end
  end

  def wallet_controller_data(chain: nil, requires_chain: false, linked: nil)
    linked ||= current_user.wallets.active.pluck(:address)
    { controller: "wallet", wallet_user_id_value: current_user.id.to_s, wallet_linked_addresses_value: linked.to_json,
      wallet_checksums_value: linked.to_h { |address| [ address, checksum_address(address) ] }.to_json,
      wallet_chain_value: chain ? chain.browser_config.to_json : "{}", wallet_requires_chain_value: requires_chain.to_s }
  end
end

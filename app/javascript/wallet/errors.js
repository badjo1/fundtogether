// Every failure the wallet and Safe layers can report, with its Dutch text.
// `neutral` means the user chose this (no error styling). `refusal` means we blocked an unsafe action.

const NEUTRAL = new Set(["user_rejected"])
const GAS_REFUSAL = "Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd."

export const MESSAGES = Object.freeze({
  // Wallet
  user_rejected: "Geannuleerd in je wallet. Er is niets gebeurd.",
  wallet_busy: "Je wallet heeft nog een verzoek openstaan. Open je wallet en rond dat eerst af.",
  unauthorized: "Je wallet geeft geen toegang. Verbind je wallet opnieuw.",
  unsupported_method: "Je wallet ondersteunt deze actie niet. Probeer het in een andere wallet.",
  wallet_disconnected: "De verbinding met je wallet is verbroken. Verbind opnieuw.",
  chain_disconnected: "Je wallet heeft geen verbinding met dit netwerk. Controleer je wallet en probeer het opnieuw.",
  chain_not_added: "Dit netwerk staat nog niet in je wallet.",
  chain_switch_failed: "Het wisselen van netwerk is niet gelukt. Kies het juiste netwerk in je wallet.",
  chain_add_failed: "Het toevoegen van het netwerk is niet gelukt. Voeg het netwerk toe in je wallet.",
  wrong_network: "Je wallet staat op het verkeerde netwerk. Wissel eerst van netwerk.",
  wrong_account: "Je wallet gebruikt een ander adres dan nodig is. Kies het juiste adres in je wallet.",
  no_wallet: "Geen wallet gevonden in deze browser.",
  no_wallet_desktop: "Geen wallet gevonden in deze browser. Installeer een wallet-extensie, of gebruik je telefoon.",
  no_wallet_mobile: "Geen wallet gevonden. Open deze pagina in de browser in je wallet-app.",
  in_app_browser: "Deze browser binnen een app kan geen wallet gebruiken. Open de pagina in Safari of Chrome, of in je wallet-app.",
  wallet_choice_required: "Kies eerst welke wallet je wilt gebruiken.",
  not_connected: "Verbind eerst je wallet.",
  wallet_action_pending: "Er loopt al een verzoek naar je wallet. Rond dat eerst af.",
  stale: "Je wallet is tijdens deze actie van adres of netwerk gewisseld. Er is niets verstuurd. Begin opnieuw.",
  session_ended: "De sessie met je wallet is beëindigd. Verbind opnieuw.",
  walletconnect_unavailable: "Verbinden via WalletConnect is niet beschikbaar. Gebruik de browser in je wallet-app.",
  wallet_error: "Je wallet gaf een fout. Probeer het opnieuw.",
  address_not_linked: "Dit adres is niet gekoppeld aan je account. Koppel deze wallet eerst.",
  invalid_signature_format: "Je wallet gaf een ongeldige handtekening terug. Er is niets opgeslagen.",

  // Server
  server_rejected: "De server heeft dit geweigerd. Probeer het opnieuw.",
  server_unreachable: "De server is niet bereikbaar. Controleer je verbinding en probeer het opnieuw.",
  session_expired: "Je sessie is verlopen. Log opnieuw in.",
  challenge_mismatch: "De koppelvraag van de server klopt niet met dit adres. Er is niets ondertekend.",
  link_mismatch: "De server bevestigde een ander adres dan je wallet. Deze koppeling is niet gelukt.",

  // Chain reads
  chain_read_failed: "De blockchain kon niet worden gelezen. Probeer het zo opnieuw.",
  chain_read_mismatch: "De blockchainverbinding hoort bij een ander netwerk dan dit fonds. Er is niets gedaan.",
  receipt_timeout: "De transactie is nog niet bevestigd. Controleer de status later; verstuur hem niet opnieuw.",

  // Refusals: proposal. The policy and build codes are the ones in test/fixtures/safe_vectors.json.
  proposal_chain_mismatch: "Dit voorstel hoort bij een ander netwerk dan dit fonds. Niet ondertekenen.",
  proposal_safe_mismatch: "Dit voorstel hoort bij een andere Safe dan dit fonds. Niet ondertekenen.",
  proposal_closed: "Dit voorstel is afgesloten en kan niet meer worden ondertekend of uitgevoerd.",
  proposal_malformed: "De gegevens van dit voorstel zijn onvolledig of ongeldig. Niet ondertekenen.",
  proposal_not_reviewed: "Bekijk het voorstel eerst, voordat je ondertekent.",
  unknown_kind: "Dit soort voorstel kennen we niet. Niet ondertekenen.",
  unexpected_param: "Dit voorstel bevat gegevens die er niet in horen. Niet ondertekenen.",
  calldata_mismatch: "De voorsteldata van de server klopt niet met wat je browser berekent. Niet ondertekenen. Als de eigenaren net zijn gewijzigd, maak dan een nieuw voorstel.",
  hash_mismatch: "De hash van de server klopt niet met wat je browser berekent. Niet ondertekenen en meld dit aan je medeleden.",
  review_outdated: "Dit voorstel is veranderd sinds je het bekeek. Bekijk het opnieuw voordat je ondertekent.",
  chain_hash_mismatch: "De hash van de Safe op de blockchain klopt niet met wat je browser berekent. Niet ondertekenen.",
  hash_self_check_failed: "Twee berekeningen van de hash verschillen. Niet ondertekenen en meld dit bij FundTogether.",
  operation_not_call: "Dit voorstel gebruikt een delegatecall of onbekende bewerking. Dat is geweigerd.",
  safe_tx_gas_nonzero: GAS_REFUSAL,
  base_gas_nonzero: GAS_REFUSAL,
  gas_price_nonzero: GAS_REFUSAL,
  gas_token_nonzero: GAS_REFUSAL,
  refund_receiver_nonzero: GAS_REFUSAL,
  nonce_too_low: "Dit voorstel is verouderd: de Safe is al verder. Het kan niet meer worden uitgevoerd.",
  invalid_nonce: "De nonce van dit voorstel is ongeldig. Niet ondertekenen.",
  nonce_not_current: "Er moet eerst een eerder voorstel worden uitgevoerd of afgewezen.",
  self_call_forbidden: "Dit voorstel roept de Safe aan met een instelling die niet is toegestaan, zoals een module of guard.",
  self_call_value: "Dit voorstel stuurt geld naar de Safe zelf. Dat is geweigerd.",
  token_call_forbidden: "Dit voorstel doet iets anders met de token dan overmaken. Dat is geweigerd.",
  token_call_value: "Een tokenoverboeking mag geen netwerkmunt meesturen. Dat is geweigerd.",
  malformed_calldata: "De voorsteldata is ongeldig gecodeerd. Dat is geweigerd.",
  unknown_target_data: "Dit voorstel roept een onbekend contract aan. Dat is geweigerd.",
  empty_call: "Dit voorstel doet niets: geen bedrag en geen data. Dat is geweigerd.",
  to_forbidden: "Dit doeladres is niet toegestaan.",
  token_not_allowed: "Deze token staat niet op de lijst van toegestane tokens voor dit netwerk.",
  token_mismatch: "De tokengegevens van de server kloppen niet met de blockchain. Niet ondertekenen.",
  invalid_address: "Dit adres is ongeldig. Controleer het adres en de hoofdletters.",
  recipient_forbidden: "Dit ontvangstadres is niet toegestaan.",
  invalid_amount: "Vul een geldig bedrag in.",
  ambiguous_amount: "Bedoel je met de punt duizendtallen of decimalen? Bedoel je 1 euro, schrijf dan 1,00. Bedoel je duizend, schrijf dan 1000.",
  insufficient_fund_balance: "Er staat te weinig in het fonds voor dit voorstel. Stort bij, trek het voorstel in of wijs het af. Er is niets verstuurd.",
  safe_has_guard: "Deze Safe heeft een guard, die uitvoering kan blokkeren. Stuur er geen geld heen en waarschuw je groep.",
  safe_has_modules: "Deze Safe heeft een module, die geld kan verplaatsen zonder handtekeningen. Stuur er geen geld heen en waarschuw je groep.",
  safe_bad_fallback: "Deze Safe heeft een onverwachte instelling (fallback handler). Stuur er geen geld heen en waarschuw je groep.",
  too_many_decimals: "Dit bedrag heeft te veel cijfers achter de komma.",
  amount_too_large: "Dit bedrag is te groot.",
  owner_forbidden: "Dit adres kan geen eigenaar zijn.",
  owner_unknown: "Dit adres is geen eigenaar van de Safe.",
  owner_exists: "Dit adres is al eigenaar van de Safe.",
  last_owner: "De laatste eigenaar kan niet worden verwijderd.",
  threshold_out_of_range: "Dit aantal handtekeningen past niet bij het aantal eigenaren.",
  threshold_unchanged: "Dit aantal handtekeningen geldt al.",
  safe_not_canonical: "Deze Safe gebruikt niet het standaardcontract. Er is niets gedaan.",

  // Signing and execution
  not_owner: "Dit adres is geen eigenaar van de Safe en kan niet ondertekenen.",
  already_signed: "Je hebt dit voorstel al ondertekend.",
  signature_mismatch: "De handtekening komt niet van het verbonden adres. Er is niets opgeslagen.",
  not_enough_signatures: "Er zijn nog niet genoeg geldige handtekeningen van huidige eigenaren.",
  execution_reverted: "De transactie is teruggedraaid. Er is niets uitgevoerd en je kunt het opnieuw proberen.",
  execution_failed: "De Safe voerde het voorstel niet uit, maar de nonce is wel verbruikt. Maak een nieuw voorstel.",
  execution_unconfirmed: "De transactie is verwerkt, maar zonder uitvoering door de Safe. Dit voorstel is niet uitgevoerd.",
  simulation_failed: "De uitvoering zou mislukken. Er is niets verstuurd.",
  insufficient_gas: "Je wallet heeft te weinig tegoed om de netwerkkosten (gas) te betalen. Zet eerst wat op deze wallet.",

  // Deployment
  deployment_malformed: "De gegevens van de Safe zijn onvolledig of ongeldig. Er is niets verstuurd.",
  initializer_mismatch: "De instellingen van de server kloppen niet met wat je browser berekent. Er is niets verstuurd.",
  address_mismatch: "Het Safe-adres van de server klopt niet met wat je browser berekent. Er is niets verstuurd.",
  deployment_contract_mismatch: "De server noemt niet de standaard Safe-contracten. Er is niets verstuurd.",
  deployment_intent_mismatch: "De eigenaren of het aantal handtekeningen wijken af van wat je hebt gekozen. Er is niets verstuurd.",
  risk_not_acknowledged: "Bevestig eerst het risico van dit aantal handtekeningen.",
  deploy_failed: "Het aanmaken van de Safe is mislukt. Er is geen Safe aangemaakt.",
  deployed_state_mismatch: "De Safe op dit adres heeft andere instellingen dan verwacht. Gebruik deze Safe niet.",

  // Contribution
  safe_not_deployed: "Deze Safe bestaat nog niet op dit netwerk. Stuur er geen geld naartoe.",
  insufficient_token: "Je wallet heeft niet genoeg saldo van deze token.",
  transfer_unconfirmed: "De transactie is verwerkt, maar de overboeking is er niet in gevonden. Controleer je wallet.",
  transfer_reverted: "De overboeking is teruggedraaid. Er is geen geld verplaatst."
})

// Contract revert codes from Safe 1.4.1.
export const SAFE_REVERTS = Object.freeze({
  GS010: "Te weinig gas voor deze uitvoering.",
  GS013: "De actie in dit voorstel mislukte. Er is niets uitgevoerd en de nonce is niet verbruikt.",
  GS020: "Er zijn te weinig handtekeningen.",
  GS021: "Een contracthandtekening is ongeldig.",
  GS022: "Een contracthandtekening is ongeldig.",
  GS023: "Een contracthandtekening is ongeldig.",
  GS024: "Een contracthandtekening is ongeldig.",
  GS025: "Deze hash is niet goedgekeurd.",
  GS026: "Een handtekening komt niet van een huidige eigenaar, of past niet bij deze nonce.",
  GS027: "Een contracthandtekening past niet bij dit voorstel.",
  GS030: "Alleen eigenaren kunnen goedkeuren."
})

export class WalletError extends Error {
  constructor(code, { message, cause, details, refusal = false } = {}) {
    super(message || MESSAGES[code] || MESSAGES.wallet_error)
    this.name = "WalletError"
    this.code = code
    this.neutral = NEUTRAL.has(code)
    this.refusal = refusal
    this.details = details
    if (cause !== undefined) this.cause = cause
  }

  toDetail() {
    return { code: this.code, message: this.message, neutral: this.neutral, refusal: this.refusal, details: this.details }
  }
}

export function refuse(code, details) {
  return new WalletError(code, { refusal: true, details })
}

function numericCode(error) {
  const code = Number(error?.code)
  return Number.isFinite(code) ? code : null
}

// MetaMask mobile wraps 4902 in -32603 with data.originalError; others nest under cause or error.
function unwrap(error) {
  let current = error
  for (let depth = 0; depth < 4 && current; depth += 1) {
    const inner = current.data?.originalError || current.originalError || current.cause || current.error
    if (numericCode(current) !== -32603 && numericCode(current) !== null) return current
    if (!inner || typeof inner !== "object") return current
    current = inner
  }
  return current
}

function messageOf(error) {
  return String(error?.message || error?.reason || "")
}

export function normalizeError(raw) {
  if (raw instanceof WalletError) return raw

  const error = unwrap(raw)
  const code = numericCode(error)
  const text = `${messageOf(raw)} ${messageOf(error)}`

  if (code === 4001 || error?.code === "ACTION_REJECTED") return new WalletError("user_rejected", { cause: raw })
  if (code === -32002) return new WalletError("wallet_busy", { cause: raw })
  if (code === 4100) return new WalletError("unauthorized", { cause: raw })
  if (code === 4200) return new WalletError("unsupported_method", { cause: raw })
  if (code === 4900) return new WalletError("wallet_disconnected", { cause: raw })
  if (code === 4901) return new WalletError("chain_disconnected", { cause: raw })
  if (code === 4902 || /unrecognized chain|chain .*not.* added|unknown chain/i.test(text)) {
    return new WalletError("chain_not_added", { cause: raw })
  }
  // WalletConnect-range and wallet-specific rejections carry no standard code.
  if (((code >= 5000 && code < 6000) || code === null) && /reject|denied|declin|cancel/i.test(text)) {
    return new WalletError("user_rejected", { cause: raw })
  }
  if (/insufficient funds/i.test(text)) return new WalletError("insufficient_gas", { cause: raw })

  const revert = revertCode(raw)
  if (revert) return new WalletError("simulation_failed", { message: `${MESSAGES.simulation_failed} ${SAFE_REVERTS[revert]}`, cause: raw, details: { revert } })

  return new WalletError("wallet_error", { cause: raw })
}

// Finds a GSxxx code in a revert message or in ABI-encoded Error(string) data, at any nesting level.
export function revertCode(raw) {
  const seen = new Set()
  const walk = (value, depth) => {
    if (value === null || value === undefined || depth > 5) return null
    if (typeof value === "string") {
      const direct = value.match(/GS0[0-9]{2}/)
      if (direct && SAFE_REVERTS[direct[0]]) return direct[0]
      // "GS013" hex-encoded inside revert data.
      const hex = value.toLowerCase().match(/4753303[0-9]{3}/)
      if (hex) {
        const decoded = hex[0].match(/../g).map((byte) => String.fromCharCode(parseInt(byte, 16))).join("")
        if (SAFE_REVERTS[decoded]) return decoded
      }
      return null
    }
    if (typeof value !== "object" || seen.has(value)) return null
    seen.add(value)
    for (const key of ["data", "message", "reason", "originalError", "cause", "error"]) {
      const found = walk(value[key], depth + 1)
      if (found) return found
    }
    return null
  }
  return walk(raw, 0)
}

export const STEP_MESSAGES = Object.freeze({
  // Link
  challenge: "Koppelvraag ophalen…",
  sign_message: "Onderteken het bericht in je wallet. Dit kost niets en verplaatst geen geld.",
  saving_link: "Koppeling opslaan…",
  // Shared
  verifying: "Gegevens controleren tegen de blockchain…",
  checking_gas: "Netwerkkosten controleren…",
  confirm_in_wallet: "Bevestig de transactie in je wallet.",
  saving: "Opslaan…",
  waiting_receipt: "Wachten op bevestiging van de blockchain…",
  // Deploy
  preparing: "Safe voorbereiden…",
  verifying_deployment: "De nieuwe Safe controleren op de blockchain…",
  // Proposal
  loading: "Voorstel ophalen…",
  sign_typed_data: "Controleer de gegevens en onderteken in je wallet.",
  saving_signature: "Handtekening opslaan…",
  // Contribution
  checking_balance: "Saldo controleren…",
  // Results. Each is published only after the chain or the server has confirmed it.
  linked: "Wallet gekoppeld.",
  deployed: "De Safe is aangemaakt en gecontroleerd op de blockchain.",
  reviewed: "Gecontroleerd. Vergelijk de gegevens hierboven met wat je wallet laat zien.",
  signed: "Je handtekening is opgeslagen.",
  checked: "Handtekeningen gecontroleerd tegen de blockchain.",
  executed: "Het voorstel is uitgevoerd op de blockchain.",
  contributed: "Je bijdrage staat op de blockchain. Hij is definitief zodra het netwerk hem heeft bevestigd."
})

export const WALLET_TEXT = Object.freeze({
  unlinked: "Deze wallet is verbonden, maar nog niet gekoppeld aan je account.",
  open_wallet: "Wacht je wallet op jou? Open je wallet om verder te gaan.",
  offer_reset: "Geen reactie van je wallet. Je kunt het opnieuw proberen."
})

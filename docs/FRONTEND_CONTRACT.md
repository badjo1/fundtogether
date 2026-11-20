# Wallet and Safe: contract for the screens

What views can rely on. Controllers contain no business logic and render no HTML: the page owns the markup
and reacts to data attributes and events. Rules from `docs/ARCHITECTURE.md` still apply: no inline scripts,
pages pass data through `data-*-value`, and addresses are shown in full and checksummed on signing screens.

## Shared rules

- **Connected is not linked.** Only `status: "ready"` (or the server's list of wallets) means a linked wallet.
- **Success events fire only after confirmation.** `linked` and `signed` after the server accepted; `deployed`,
  `executed` and `contributed` after the receipt and chain checks. Show "in behandeling" until then, and never
  a success state on `waiting_receipt`.
- **Never a silent zero.** On `error`, balance fields are emptied. Show the message.
- **Turbo.** All controllers clear their dynamic UI on `turbo:before-cache` and need a fresh review after a restore.
  Mark the wallet pill `data-turbo-permanent` to avoid flicker. The session itself survives visits.
- **Lazy.** `safe-deploy`, `proposal-sign`, `proposal-execute` and `contribute` load viem (32 KB gz) on first action.
- Every flow element gets `data-flow-state="<step>"`, or `"error"`. Style from this.
- A `message` target, if present, receives the Dutch text, with `data-tone` set to `neutral`, `refusal` or `error`
  on failures. `neutral` is a user's own cancel: no error styling. `refusal` means we blocked something unsafe.
- `field` targets are filled by name: `<span data-proposal-sign-target="field" data-field="safeTxHash"></span>`.
  Text only.

## Chain config

The `chain` value on every controller below: the entry from `config/chains.yml`.

```erb
data-wallet-chain-value="<%= @account.chain.browser_config.to_json %>"
```

**Never render `chain.rpc_urls`.** It can include operator endpoints with keys from `FUNDTOGETHER_RPC_URLS_*`.
`browser_config` carries only `public_rpc_urls` from `chains.yml`, the same origins the CSP allows. The token here
is the allowlist: a proposal or contribution for any other token is refused.

## `wallet`

Values: `user-id` String, `linked-addresses` Array (lowercase, from `GET /wallets`), `checksums` Object (lowercase
address to EIP-55, server-made for the linked wallets, so the `address` field reads checksummed without loading viem;
an unknown address stays lowercase), `chain` Object, `requires-chain` Boolean.

Targets: `message`, `field` (`address`, `walletName`, `status`), `providerList`, `providerTemplate`.

```erb
<template data-wallet-target="providerTemplate">
  <button type="button" data-action="wallet#connectWallet">
    <img data-wallet-icon alt=""><span data-wallet-name></span>
  </button>
</template>
```

A `<template>` is cloned for each wallet. The controller sets `data-wallet-key-param`, name as text, and a
`data:` image icon only.

Actions: `connectWallet` (optional `data-wallet-key-param`), `disconnectWallet`, `switchChain`, `reset`
(offer it when `data-wallet-banner="offer_reset"`).

Element: `data-wallet-state`, `data-wallet-status`, `data-wallet-banner`.

Event `wallet:state`: `{ state, status, address, chainId, wallet, wallets, banner, notice, environment, message }`.
`environment`: `{ mobile, ios, android, socialWebview, walletBrowser }`. Event `wallet:error`.

| `state` | Meaning | UI |
|---|---|---|
| `idle`, `discovering`, `restoring` | Starting, under 1 s | Neutral placeholder |
| `no_wallet` | Nothing found; late wallets still count | Message depends on device. Offer the handoff on desktop |
| `disconnected` | Wallets exist | Picker or connect button |
| `requesting_accounts` | Wallet prompt open | "Open je wallet" |
| `wallet_busy` | Wallet has a pending request | Message plus retry on click |
| `connected` | Has an address. Read `status` | |
| `switching_chain`, `adding_chain` | Wallet prompt open | |
| `awaiting_signature`, `submitting` | Flow in progress | Banner texts below |
| `stale` | Address or chain changed mid-flow. Nothing was sent | Message, then restart |

| `status` (when connected) | UI |
|---|---|
| `unlinked` | Offer `wallet-link` |
| `address_mismatch` | "Andere wallet": switch in the wallet, or link this one. Never auto-link |
| `wrong_network` | Offer `wallet#switchChain` |
| `ready` | Actions available |

Otherwise `status` equals `state`. `disconnectWallet` ends our use of the wallet; the wallet's own permission
stays until the user revokes it there, and the page should not claim otherwise.

## `wallet-link`

Values: `challenges-url`, `wallets-url`, `handoffs-url`. Target: `message`.
Actions: `link`, `handoff`.
Events: `step`, `error`, `linked` `{ wallet }`, `handoff` `{ url, expiresAt, deepLinks: { metamask, trust } }`.
Steps: `challenge`, `sign_message`, `saving_link`, `linked`. Linking does not require the right network. The message's
first line must name the page's own host (`location.host`), or the flow refuses with `challenge_mismatch` before signing.

There is no QR library in the bundle. Use a server-rendered QR, or show the link.

## `safe-deploy`

Values: `url` (`/accounts/:id/safe`), `chain`, `create-params` Object (the POST body, empty to use the stored
configuration), `acknowledge-risk` Boolean. Target: `message`. Action: `deploy`.
Events: `step`, `error`, `hint-failed`, `deployed` `{ safeAddress, txHash }`.
Steps: `preparing`, `verifying`, `checking_gas`, `confirm_in_wallet`, `saving`, `waiting_receipt`,
`verifying_deployment`, `deployed`.
Reload the page after `deployed`: the server's own verification decides `active`.

## `proposal-sign`

Values: `proposal-url`, `signatures-url`, `chain`, `safe-address`, `linked-addresses`. Targets: `message`, `field`.
Actions: `review`, then `sign`. `sign` refuses without a review on this page.
Events: `step`, `error`, `reviewed` `{ display }`, `signed` `{ proposal, signer }`.
Steps: `loading`, `verifying`, `reviewed`; then `loading`, `verifying`, `sign_typed_data`, `saving_signature`, `signed`.

`display` and `field` names: `kind`, `title`, `summary`, `recipient`, `amount`, `symbol`, `owner`, `network`, `chainId`,
`safeAddress`, `to`, `value`, `data`, `operation`, `nonce`, `chainNonce`, `threshold`, `signatureCount`, `domainHash`,
`messageHash`, `safeTxHash`. All are computed locally. Show `summary`, full addresses, `operation`, and the three
hashes, and tell the user to compare them with their wallet and an off-origin verifier. Server text is limited to
`title`. Treat it as untrusted: bidi, zero-width and control characters are removed from it on both sides, and pages
render it inside `<bdi>` and label it as the proposer's text.

## `proposal-execute`

Values: `proposal-url`, `execution-url`, `sync-url`, `chain`, `safe-address`. Targets: `message`, `field`.
Actions: `check`, `execute`. Element: `data-execution-ready`.
Events: `step`, `error`, `hint-failed`, `checked` `{ ready, sufficient, isNext, have, need, display, proposal }`
(`ready` is false when the Safe cannot pay; `execute` refuses with `insufficient_fund_balance` before any prompt),
`executed` `{ outcome, txHash, safeTxHash }`.
Steps: `loading`, `verifying`, `checked`; then `loading`, `verifying`, `checking_gas`, `confirm_in_wallet`, `saving`,
`waiting_receipt`, `executed`.
`execution_failed` means the nonce was consumed and a new proposal is needed. `execution_reverted` can be retried.
`receipt_timeout` is not a failure: tell the user not to send again.

## `contribute`

Values: `sync-url`, `safe-url` (`/accounts/:id/safe`), `chain`, `token-address`, `safe-address`. Targets: `message`,
`field`, `amount` (text input), `destination` (optional).
With a `destination` target, the controller checks the Safe on load (`checkDestination`): code, canonical singleton, no
guard, canonical fallback handler, no modules, and the address recomputed from the server's deployment data. It fills
`destinationAddress`, `destinationOwners`, `destinationThreshold`, `destinationStatus` and sets `data-destination-state`
to `verified` or `refused`. `contribute` runs the same check again before any wallet prompt. A browser cannot tell
whether the owners are the right people: the page shows them for the person to recognise.
Use `inputmode="decimal"`, not `type="number"`: amounts stay strings. Both `12,50` and `12.50` work. A dot followed by
exactly three digits (`1.000`) is refused as `ambiguous_amount`, in JS and in Ruby. `amount-echo` (values `decimals`,
`symbol`; targets `input`, `output`) shows "Dat is precies 1,50 EURC." under the field while typing.
Actions: `contribute`, `refreshBalances`. `field` names: `fundBalance`, `walletBalance`, `gasBalance`, `symbol`, `gasSymbol`.
Events: `step`, `error`, `hint-failed`, `balances` `{ fund, wallet, gas }` (each `{ units, formatted, symbol }`, or null),
`contributed` `{ txHash, units, formatted, symbol }`.
Steps: `checking_balance`, `checking_gas`, `confirm_in_wallet`, `waiting_receipt`, `contributed`.
After `contributed` the money is on-chain but the fund's activity list follows chain sync: show it as "in behandeling".

## `hint-failed`

The transaction exists, but telling our server failed. Chain sync catches up, so show no error. Log it if useful.

## Errors

Events carry `{ code, message, neutral, refusal, details }`. Show `message`. Server refusals arrive as
`server_rejected`, with the server's own Dutch `message` and its code in `details.error`.

| Code | Tekst |
|---|---|
| `user_rejected` | Geannuleerd in je wallet. Er is niets gebeurd. |
| `wallet_busy` | Je wallet heeft nog een verzoek openstaan. Open je wallet en rond dat eerst af. |
| `unauthorized` | Je wallet geeft geen toegang. Verbind je wallet opnieuw. |
| `unsupported_method` | Je wallet ondersteunt deze actie niet. Probeer het in een andere wallet. |
| `wallet_disconnected` | De verbinding met je wallet is verbroken. Verbind opnieuw. |
| `chain_disconnected` | Je wallet heeft geen verbinding met dit netwerk. Controleer je wallet en probeer het opnieuw. |
| `chain_not_added` | Dit netwerk staat nog niet in je wallet. |
| `chain_switch_failed` | Het wisselen van netwerk is niet gelukt. Kies het juiste netwerk in je wallet. |
| `chain_add_failed` | Het toevoegen van het netwerk is niet gelukt. Voeg het netwerk toe in je wallet. |
| `wrong_network` | Je wallet staat op het verkeerde netwerk. Wissel eerst van netwerk. |
| `wrong_account` | Je wallet gebruikt een ander adres dan nodig is. Kies het juiste adres in je wallet. |
| `no_wallet` | Geen wallet gevonden in deze browser. |
| `no_wallet_desktop` | Geen wallet gevonden in deze browser. Installeer een wallet-extensie, of gebruik je telefoon. |
| `no_wallet_mobile` | Geen wallet gevonden. Open deze pagina in de browser in je wallet-app. |
| `in_app_browser` | Deze browser binnen een app kan geen wallet gebruiken. Open de pagina in Safari of Chrome, of in je wallet-app. |
| `wallet_choice_required` | Kies eerst welke wallet je wilt gebruiken. |
| `not_connected` | Verbind eerst je wallet. |
| `wallet_action_pending` | Er loopt al een verzoek naar je wallet. Rond dat eerst af. |
| `stale` | Je wallet is tijdens deze actie van adres of netwerk gewisseld. Er is niets verstuurd. Begin opnieuw. |
| `session_ended` | De sessie met je wallet is beëindigd. Verbind opnieuw. |
| `walletconnect_unavailable` | Verbinden via WalletConnect is niet beschikbaar. Gebruik de browser in je wallet-app. |
| `wallet_error` | Je wallet gaf een fout. Probeer het opnieuw. |
| `address_not_linked` | Dit adres is niet gekoppeld aan je account. Koppel deze wallet eerst. |
| `invalid_signature_format` | Je wallet gaf een ongeldige handtekening terug. Er is niets opgeslagen. |
| `server_rejected` | De server heeft dit geweigerd. Probeer het opnieuw. |
| `server_unreachable` | De server is niet bereikbaar. Controleer je verbinding en probeer het opnieuw. |
| `session_expired` | Je sessie is verlopen. Log opnieuw in. |
| `challenge_mismatch` | De koppelvraag van de server klopt niet met dit adres. Er is niets ondertekend. |
| `link_mismatch` | De server bevestigde een ander adres dan je wallet. Deze koppeling is niet gelukt. |
| `chain_read_failed` | De blockchain kon niet worden gelezen. Probeer het zo opnieuw. |
| `chain_read_mismatch` | De blockchainverbinding hoort bij een ander netwerk dan dit fonds. Er is niets gedaan. |
| `receipt_timeout` | De transactie is nog niet bevestigd. Controleer de status later; verstuur hem niet opnieuw. |
| `proposal_chain_mismatch` | Dit voorstel hoort bij een ander netwerk dan dit fonds. Niet ondertekenen. |
| `proposal_safe_mismatch` | Dit voorstel hoort bij een andere Safe dan dit fonds. Niet ondertekenen. |
| `proposal_closed` | Dit voorstel is afgesloten en kan niet meer worden ondertekend of uitgevoerd. |
| `proposal_malformed` | De gegevens van dit voorstel zijn onvolledig of ongeldig. Niet ondertekenen. |
| `proposal_not_reviewed` | Bekijk het voorstel eerst, voordat je ondertekent. |
| `unknown_kind` | Dit soort voorstel kennen we niet. Niet ondertekenen. |
| `unexpected_param` | Dit voorstel bevat gegevens die er niet in horen. Niet ondertekenen. |
| `calldata_mismatch` | De voorsteldata van de server klopt niet met wat je browser berekent. Niet ondertekenen. Als de eigenaren net zijn gewijzigd, maak dan een nieuw voorstel. |
| `hash_mismatch` | De hash van de server klopt niet met wat je browser berekent. Niet ondertekenen en meld dit aan je medeleden. |
| `review_outdated` | Dit voorstel is veranderd sinds je het bekeek. Bekijk het opnieuw voordat je ondertekent. |
| `chain_hash_mismatch` | De hash van de Safe op de blockchain klopt niet met wat je browser berekent. Niet ondertekenen. |
| `hash_self_check_failed` | Twee berekeningen van de hash verschillen. Niet ondertekenen en meld dit bij FundTogether. |
| `operation_not_call` | Dit voorstel gebruikt een delegatecall of onbekende bewerking. Dat is geweigerd. |
| `safe_tx_gas_nonzero` | Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd. |
| `base_gas_nonzero` | Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd. |
| `gas_price_nonzero` | Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd. |
| `gas_token_nonzero` | Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd. |
| `refund_receiver_nonzero` | Dit voorstel laat de Safe gas vergoeden. Dat is geweigerd. |
| `nonce_too_low` | Dit voorstel is verouderd: de Safe is al verder. Het kan niet meer worden uitgevoerd. |
| `invalid_nonce` | De nonce van dit voorstel is ongeldig. Niet ondertekenen. |
| `nonce_not_current` | Er moet eerst een eerder voorstel worden uitgevoerd of afgewezen. |
| `self_call_forbidden` | Dit voorstel roept de Safe aan met een instelling die niet is toegestaan, zoals een module of guard. |
| `self_call_value` | Dit voorstel stuurt geld naar de Safe zelf. Dat is geweigerd. |
| `token_call_forbidden` | Dit voorstel doet iets anders met de token dan overmaken. Dat is geweigerd. |
| `token_call_value` | Een tokenoverboeking mag geen netwerkmunt meesturen. Dat is geweigerd. |
| `malformed_calldata` | De voorsteldata is ongeldig gecodeerd. Dat is geweigerd. |
| `unknown_target_data` | Dit voorstel roept een onbekend contract aan. Dat is geweigerd. |
| `empty_call` | Dit voorstel doet niets: geen bedrag en geen data. Dat is geweigerd. |
| `to_forbidden` | Dit doeladres is niet toegestaan. |
| `token_not_allowed` | Deze token staat niet op de lijst van toegestane tokens voor dit netwerk. |
| `token_mismatch` | De tokengegevens van de server kloppen niet met de blockchain. Niet ondertekenen. |
| `invalid_address` | Dit adres is ongeldig. Controleer het adres en de hoofdletters. |
| `recipient_forbidden` | Dit ontvangstadres is niet toegestaan. |
| `invalid_amount` | Vul een geldig bedrag in. |
| `ambiguous_amount` | Bedoel je met de punt duizendtallen of decimalen? Bedoel je 1 euro, schrijf dan 1,00. Bedoel je duizend, schrijf dan 1000. |
| `insufficient_fund_balance` | Er staat te weinig in het fonds voor dit voorstel. Stort bij, trek het voorstel in of wijs het af. Er is niets verstuurd. |
| `safe_has_guard` | Deze Safe heeft een guard, die uitvoering kan blokkeren. Stuur er geen geld heen en waarschuw je groep. |
| `safe_has_modules` | Deze Safe heeft een module, die geld kan verplaatsen zonder handtekeningen. Stuur er geen geld heen en waarschuw je groep. |
| `safe_bad_fallback` | Deze Safe heeft een onverwachte instelling (fallback handler). Stuur er geen geld heen en waarschuw je groep. |
| `too_many_decimals` | Dit bedrag heeft te veel cijfers achter de komma. |
| `amount_too_large` | Dit bedrag is te groot. |
| `owner_forbidden` | Dit adres kan geen eigenaar zijn. |
| `owner_unknown` | Dit adres is geen eigenaar van de Safe. |
| `owner_exists` | Dit adres is al eigenaar van de Safe. |
| `last_owner` | De laatste eigenaar kan niet worden verwijderd. |
| `threshold_out_of_range` | Dit aantal handtekeningen past niet bij het aantal eigenaren. |
| `threshold_unchanged` | Dit aantal handtekeningen geldt al. |
| `safe_not_canonical` | Deze Safe gebruikt niet het standaardcontract. Er is niets gedaan. |
| `not_owner` | Dit adres is geen eigenaar van de Safe en kan niet ondertekenen. |
| `already_signed` | Je hebt dit voorstel al ondertekend. |
| `signature_mismatch` | De handtekening komt niet van het verbonden adres. Er is niets opgeslagen. |
| `not_enough_signatures` | Er zijn nog niet genoeg geldige handtekeningen van huidige eigenaren. |
| `execution_reverted` | De transactie is teruggedraaid. Er is niets uitgevoerd en je kunt het opnieuw proberen. |
| `execution_failed` | De Safe voerde het voorstel niet uit, maar de nonce is wel verbruikt. Maak een nieuw voorstel. |
| `execution_unconfirmed` | De transactie is verwerkt, maar zonder uitvoering door de Safe. Dit voorstel is niet uitgevoerd. |
| `simulation_failed` | De uitvoering zou mislukken. Er is niets verstuurd. |
| `insufficient_gas` | Je wallet heeft te weinig tegoed om de netwerkkosten (gas) te betalen. Zet eerst wat op deze wallet. |
| `deployment_malformed` | De gegevens van de Safe zijn onvolledig of ongeldig. Er is niets verstuurd. |
| `initializer_mismatch` | De instellingen van de server kloppen niet met wat je browser berekent. Er is niets verstuurd. |
| `address_mismatch` | Het Safe-adres van de server klopt niet met wat je browser berekent. Er is niets verstuurd. |
| `deployment_contract_mismatch` | De server noemt niet de standaard Safe-contracten. Er is niets verstuurd. |
| `deployment_intent_mismatch` | De eigenaren of het aantal handtekeningen wijken af van wat je hebt gekozen. Er is niets verstuurd. |
| `risk_not_acknowledged` | Bevestig eerst het risico van dit aantal handtekeningen. |
| `deploy_failed` | Het aanmaken van de Safe is mislukt. Er is geen Safe aangemaakt. |
| `deployed_state_mismatch` | De Safe op dit adres heeft andere instellingen dan verwacht. Gebruik deze Safe niet. |
| `safe_not_deployed` | Deze Safe bestaat nog niet op dit netwerk. Stuur er geen geld naartoe. |
| `insufficient_token` | Je wallet heeft niet genoeg saldo van deze token. |
| `transfer_unconfirmed` | De transactie is verwerkt, maar de overboeking is er niet in gevonden. Controleer je wallet. |
| `transfer_reverted` | De overboeking is teruggedraaid. Er is geen geld verplaatst. |

Revert codes, appended to `simulation_failed`:

| Code | Tekst |
|---|---|
| `GS010` | Te weinig gas voor deze uitvoering. |
| `GS013` | De actie in dit voorstel mislukte. Er is niets uitgevoerd en de nonce is niet verbruikt. |
| `GS020` | Er zijn te weinig handtekeningen. |
| `GS021` | Een contracthandtekening is ongeldig. |
| `GS022` | Een contracthandtekening is ongeldig. |
| `GS023` | Een contracthandtekening is ongeldig. |
| `GS024` | Een contracthandtekening is ongeldig. |
| `GS025` | Deze hash is niet goedgekeurd. |
| `GS026` | Een handtekening komt niet van een huidige eigenaar, of past niet bij deze nonce. |
| `GS027` | Een contracthandtekening past niet bij dit voorstel. |
| `GS030` | Alleen eigenaren kunnen goedkeuren. |


## Step texts

| Stap | Tekst |
|---|---|
| `challenge` | Koppelvraag ophalen… |
| `sign_message` | Onderteken het bericht in je wallet. Dit kost niets en verplaatst geen geld. |
| `saving_link` | Koppeling opslaan… |
| `verifying` | Gegevens controleren tegen de blockchain… |
| `checking_gas` | Netwerkkosten controleren… |
| `confirm_in_wallet` | Bevestig de transactie in je wallet. |
| `saving` | Opslaan… |
| `waiting_receipt` | Wachten op bevestiging van de blockchain… |
| `preparing` | Safe voorbereiden… |
| `verifying_deployment` | De nieuwe Safe controleren op de blockchain… |
| `loading` | Voorstel ophalen… |
| `sign_typed_data` | Controleer de gegevens en onderteken in je wallet. |
| `saving_signature` | Handtekening opslaan… |
| `checking_balance` | Saldo controleren… |
| `linked` | Wallet gekoppeld. |
| `deployed` | De Safe is aangemaakt en gecontroleerd op de blockchain. |
| `reviewed` | Gecontroleerd. Vergelijk de gegevens hierboven met wat je wallet laat zien. |
| `signed` | Je handtekening is opgeslagen. |
| `checked` | Handtekeningen gecontroleerd tegen de blockchain. |
| `executed` | Het voorstel is uitgevoerd op de blockchain. |
| `contributed` | Je bijdrage staat op de blockchain. Hij is definitief zodra het netwerk hem heeft bevestigd. |

## Wallet texts

| Sleutel | Tekst |
|---|---|
| `unlinked` | Deze wallet is verbonden, maar nog niet gekoppeld aan je account. |
| `open_wallet` | Wacht je wallet op jou? Open je wallet om verder te gaan. |
| `offer_reset` | Geen reactie van je wallet. Je kunt het opnieuw proberen. |

## Ramp page

`account_ramp_path(account)` and `leave_account_ramp_path(account, route:)` are built by the ramps work, not by a Stimulus
controller. See `docs/RAMPS.md`. The page links to `account_contribute_path`, `wallet_page_path` and:

```erb
new_account_proposal_page_path(account, kind: "transfer_token", recipient: "<lowercase address>")
```

The proposal form needs to:

- Pre-select or pre-fill `recipient` from that query parameter. The amount stays empty.
- Treat the parameter as untrusted. Anyone can craft this URL, so never submit by itself, show the address in full, and
  say whether it is one of the current user's own wallets.

The ramp page has no entry in the sidebar or fund navigation of its own. That link belongs to the shared layout.

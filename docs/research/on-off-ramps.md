# 05: On-ramp and off-ramp research for FundTogether

Date checked: 2026-11-08. Not legal advice; the regulatory sections are flags for a lawyer.

Evidence labels:
- **[V]** verified now against a primary source (doc text read, or live header/API response).
- **[S]** static analysis of a provider's published code, not a runtime test.
- **[2]** secondary source, or only a search snippet of a primary page.
- **[U]** unverified.

## 1. Bottom line

1. **Do not make the shared Safe the destination of a provider purchase by default.** Some providers can technically deliver to a Safe, but their terms and account models treat the address as one customer's own.
   - Mt Pelerin rejects an address "already registered on another Mt Pelerin account" and says "common addresses are not permitted". [V]
   - Its terms require acting "for your own benefit" and not "on behalf and/or to the interest of any other person". [V]
   - Monerium's terms bar using the service "on behalf of any third party... without our prior written approval". [V]
   - Default flow: **member buys into their own wallet, then makes a normal contribution transfer to the Safe.** This also gives per-member attribution on-chain.
2. **On-ramp primary: Monerium, linked out, no integration.** The member opens their own Monerium account, links their own wallet, sends SEPA from their bank app, receives EURe, then contributes. No FundTogether key, contract or backend. No FX exposure.
3. **Off-ramp primary: a two-step flow.** A Safe proposal pays EURe to the recipient's own wallet. The recipient then redeems at Monerium to their own IBAN. No provider deposit address appears in a multisig proposal, which removes expiry, refund and "is this address really the provider?" risks.
4. **Mt Pelerin is usable without a key by direct link, but it should not be the unreviewed default for Dutch users.** It is not in ESMA's CASP register by name. [V] After the MiCA transition ended on 1 July 2026, a button or revenue share from FundTogether may undercut any reverse-solicitation position. Treat it as a fallback behind legal review, and never with `rfr`.
5. **Bitvavo does not reach any candidate chain.** Its public API lists USDC and EURC on `ETH` only. [V] It is not a path to Gnosis, Base, Arbitrum or Polygon without a separate bridge step.
6. **Iframes are not worth it.** Monerium blocks framing by unlisted origins, Coinbase denies it, MoonPay needs an allowlisted domain, Transak needs a signed backend session. Only Mt Pelerin is open by headers, and its iframe needs a production key issued only to live projects.

## 2. Mt Pelerin `_ctkn` conflict: resolved

The docs do conflict: the params table says "Mandatory", the Direct links section says no key is required (https://developers.mtpelerin.com/llms-full.txt), and the direct-link examples still pass a published key `954139b2-ef3e-4914-82ea-33192d3f43d3`. [V]

The widget code explains it. [S] In `/js/app~748942c6.e7afd0af.js`, `checkAccess()` computes `r`, which is true when the parent origin is in this list:

- `https://app.safe.global`
- `https://app.mtpelerin.com`
- `https://widget.mtpelerin.com`
- `https://widget-staging.mtpelerin.com`
- `https://kyb.mtpelerin.com`, `https://kyc.mtpelerin.com`, `https://otc.mtpelerin.com`

It returns `r || e.hasAccess` from an API call using `_ctkn`.

The parent lookup reads `window.parent.location.href` first. In a top-level tab, the parent is the widget itself, so the origin is `widget.mtpelerin.com` and access is granted **whatever the key**. In a third-party iframe the read throws, it falls back to `ancestorOrigins[0]`, and access depends on the key.

- **Top-level direct link: no key enforced.** Pass the documented public key anyway to match the documented URL form. It costs nothing and survives a future change.
- **Iframe or popup on our domain: needs a key tied to the origin.** Production keys require emailing hello@mtpelerin.com with a live URL ("We don't issue production keys to projects that are not live yet"). [V] Local key `bec6626e-8913-497d-9835-6e6ae9edb144` works on localhost:3000, 3001, 8080, 5173. [V] Rails' default port 3000 fits.
- **Not sandbox:** the docs describe no test mode for the widget. Treat localhost-key sessions as real-service. [V for absence in docs]
- **Runtime caveat:** I did not click through it. Server-side refusal later in the flow cannot be excluded. A browser check before shipping is required.

## 3. Comparison

| Provider | Integration requirement | EU payment | Total fee (primary citation) | Min / max | KYC | MiCA register (ESMA CSV) |
|---|---|---|---|---|---|---|
| **Monerium** | Link-out: none. OAuth: partner application, review, agreement, client ID, backend. [V] | SEPA, SEPA Instant. No card. iDEAL not offered as such; bank app transfer works. | Unclear. Former fee page 404s now; undated snippet said no fees. [2] A 0.5% figure appeared only in a snippet of a removed partner page. [2] ToS §4 says fees are in a Fee Schedule. [V] | Min 0.01; "no per-customer limits" (FAQ) [V], but ToS §14 reserves limits [V] | Full KYC: ID, selfie/liveness, proof of address [V] | EMT issuer, Central Bank of Iceland [V] |
| **Mt Pelerin** | Direct link: none [S]. Iframe: key. Card in integration: KYB + agreement. [V] | SEPA free; card/Apple/Google Pay. No iDEAL documented. | Bank, per calendar year: 0-500 free; 501-5,000 1.3%; 5,001-50,000 1.1%. Applies to the full amount, no spread claimed. Card: 2.5% to 499, then 3.8%; min CHF 1.20. [V] | Buy: none / CHF 100k. Card max CHF 5k. Sell: CHF 50 (live API: EUR 54.72), none with personal IBAN. [V] | None to CHF 999 per rolling 30 days, but phone and email required. **Unverified SEPA buys held 7 days.** Card always KYC. [V] | **Not found by name** in CASP or non-compliant list [V] |
| **Ramp Network** | `hostApiKey` documented as required; form-issued. Off-ramp requires production key with feature enabled. [V] | Manual bank, "easy bank" for select banks, card. iDEAL [U]. | Buy: bank up to 1.40%; easy bank up to 2.40%; EUR card up to 3.9%; min fee up to EUR 2.49 (page dated 2025-06-25). [V] API: 0.99-3.9%. [V] Sell: 0.99%, min EUR 1.99 [2]; current page no longer prints numbers. | Live API: EUR 6 / 15,000 [V] | Depends on tier [U] | Ramp Swaps (Ireland), 2025-12-02 [V] |
| **Transak** | KYB for production key; backend session (single use, 5 min); backend-only calls, static IP whitelist, `x-user-ip`. [V] | Public API for EUR currently lists **only card, Apple Pay, Google Pay**, EUR 4-5,387. [V] SEPA conflicts with marketing. [2] | Third-party only: about 1% SEPA, 3.5-5.5% card. [2] | See left | Tiered; thresholds [U] | **Not found by name** [V] |
| **MoonPay** | Dashboard account; signed URL with secret; **IP matching mandatory to go live**; domain allowlist for embedding. [V] | SEPA, SEPA Instant, card [2]; iDEAL [U] | "Up to 4.5%", minimum up to $3.99 direct, $4.50 via partner (from the en-ca disclosure, not EU-specific). [V] | About EUR 20 min [2] | Tiered [V] | MoonPay Europe B.V., AFM [V] |
| **Coinbase Onramp** | CDP account, session token per user (single use, 5 min), backend. [2] | EU cards [V]; SEPA/iDEAL via config endpoint [U]. Guest checkout US/UK/CA only and being discontinued 30 June 2026. [V] | Card 2.5%, ACH 0.5%, plus spread. [V] | [U] | Coinbase account for EU [V for guest limits] | Coinbase Luxembourg [V] |
| **Mercuryo** | Widget ID + secret, signature mandatory on-ramp, integration manager; sandbox IP whitelist. [2] | Visa/Mastercard per FAQ [V]; others [U] | [U] | [U] | [U] | Not found by name [V] |
| **Banxa** | Partner reference; hosted checkout via redirect/iframe. Agreement [U]. | iDEAL via hosted checkout per docs. [V] SEPA [U]. | Per quote; no schedule. [V] | [U] | Banxa-run or partner-run [V] | Not found by name. EU Internet Ventures / OSL Pay row may be related [U] |
| **Bridge (Stripe)** | Sales contact + SEPA endorsement; API key, customers. [V] | SEPA, SEPA Instant [V] | Not published [V] | [U] | Customer records [V] | Bridge Building S.A., Luxembourg, 2026-06-29 [V] |
| **Stripe Onramp** | Application, even for sandbox; front-end URL can skip account. [V] | [U] | [U] | [U] | Stripe-run [V] | **USDC on Base and Polygon "aren't supported in the EU"**; only USDC on Ethereum. [V] Rejected. |
| **Bitvavo (manual)** | None. | SEPA EUR 0; iDEAL/Wero EUR 0, max EUR 50,000. [V] | Withdraw 1.1 USDC or 0.96 EURC (`api.bitvavo.com/v2/assets`) [V]; trade fee low, tiers conflict. [V/2] | Withdraw min 1.2 USDC, 1.1 EURC [V] | Full KYC | AFM [V] |
| **Peer (ZKP2P)** | SDK + browser extension or app. | Revolut, Wise, etc. P2P. | Shown in quote. [V] | Per seller [V] | P2P | Not a CASP by name. Rejected for mainstream users. |
| **Request Network** | KYC + agreement for fiat payouts. [V] | Off-ramp only | [U] | [U] | Required | Rejected: for invoices, not for this. |
| **Peanut** | Docs unreadable by index [U] | [U] | [U] | [U] | [U] | Rejected for lack of evidence. |
| **CoW / LI.FI** | Swap only, not a ramp. | None | CoW partner fee max 100 bps, 25% service cut [V]. LI.FI docs timed out [U]. | | | Use only for EURe/USDC conversion if forced. |
| **Safe's own** | Safe iOS app uses MoonPay. [2] | | | | | Not usable from FundTogether. |

Register checked in https://www.esma.europa.eu/sites/default/files/2024-12/CASPS.csv and NCASP.csv. ESMA warns the interim register can lag. A name search can miss a provider operating under a different entity, so "not found" is not a finding of illegality.

### Token and chain matrix

| | Gnosis | Base | Arbitrum | Polygon |
|---|---|---|---|---|
| Monerium | EURe | EURe | EURe | EURe |
| Mt Pelerin | USDC, USDT, xDAI | **EURC**, USDC | USDC, USDT | USDC, USDT |
| Ramp | none of USDC/EURC/EURe under codes GNOSIS/XDAI | USDC, USDT | USDC, USDT | USDC, USDT |
| Transak | none | USDC, EURC | USDC | USDC, USDT |
| Bitvavo | none | none | none | none |
| Stripe (EU) | none | none | n/a | none |

Sources:
- Monerium: partners page and API `chain` enum list all four. [V] Per-chain EURe contract addresses were not readable (page "Loading…"); chain research must confirm.
- Mt Pelerin: docs list plus `https://api.mtpelerin.com/currencies/tokens`. The API also returns legacy tokens (jEUR, EUROe), which I excluded because docs do not list them.
- Ramp: `https://api.ramp.network/api/host-api/v3/assets?currencyCode=EUR`. Transak: `https://api.transak.com/api/v2/currencies/crypto-currencies`.

Chain implication:
- All four work with Monerium.
- **Base** has the widest fallback coverage, including a second euro token (EURC).
- **Gnosis** has no regulated-provider fallback other than Monerium and Mt Pelerin, and no euro token at Mt Pelerin.
- USDC paths add EUR/USD exposure to a euro pool, which must be disclosed.

## 4. Critical: Safe as destination

| Provider | Address rule | Contract/Safe | Undeployed Safe | Multisig satisfiable? |
|---|---|---|---|---|
| **Mt Pelerin** | Ownership proof mandatory: sign `MtPelerin-{code}`, or pass `addr`/`code`/`hash`/`chain`. Unique per user. [V] | EIP-1271 via `chain`. [V] | ERC-6492 wrapped signature accepted. [V] | Yes technically: threshold signatures. Not usable for several members, since each address binds to one account. |
| **Monerium** | Fixed message `I hereby declare that I am the address owner.` [V] | Off-chain EIP-1271 combined signatures (201), or on-chain `signMessage` with `0x` (202), polled up to 5 days. [V] | Not documented; `isValidSignature` implies deployed. [U] | Yes. Profile holder's IBAN. Each IBAN "in the individual account holder's name, not a shared account". [V] |
| **Ramp** | `userAddress` optional; no ownership proof documented. [V] | Not documented [U] | [U] | No proof asked; contract delivery unconfirmed. |
| **Transak** | `walletAddress`, `disableWalletAddressForm`. `verify-wallet-address` validates the address, not ownership. [V] | Not documented [U] | [U] | As Ramp. |
| **MoonPay** | `walletAddress` needs signed URL. "One account per user". [V] | Not documented [U] | [U] | As Ramp. |
| **Coinbase, Banxa, Mercuryo** | Set by session or params. | [U] | [U] | [U] |
| **Bitvavo and EU CASPs generally** | Send only to a wallet that belongs to you; ownership verification under Travel Rule. [2] A law-firm note puts the self-custody duty at EUR 1,000. [2] | [U] (help pages blocked to automated fetch) | [U] | A shared Safe is not cleanly "yours". |

**Answer:** Direct-to-Safe is technically possible at Mt Pelerin and Monerium, and possibly elsewhere without proof, but it fits only when **one legal or natural person genuinely owns the Safe**, such as:
- a vereniging or stichting with a Monerium business (KYB) profile, or
- a single organiser, with Monerium's written approval if others' money is involved.

Everything else goes through the signer's personal wallet.

Consequences of the personal-wallet route:
- The member needs gas on the chosen chain. Check with the chain agent; xDAI on Gnosis is cheap but still needed. Mt Pelerin also warns a sale will not start without native gas. [V]
- Show the contribution step as part of the flow, or money stops in the member's wallet.
- Do not expose a deposit address for an undeployed Safe. A counterfactual Safe can be funded, but recovery depends on later deploying with the same setup on that chain. Deploy first.

**Monerium third-party rule, exact text** (ToS §16, effective 2025-05-20): "to use the Services on behalf of any third party or to hold or carry out transactions with your clients' money without our prior written approval... you are not allowed to operate as a 'front', a 'reseller'... For example, you are not allowed to receive payments to your Monerium IBAN account from a third party and subsequently transfer the corresponding amount of e-money to that same third party." [V]

- Monerium may also require the first incoming payment to come from an account in the customer's own name. [2: KYC guide summary]
- The KYC guide also lists "Third-party payments..." among prohibited activities, while the partners page says third-party SEPA payments are supported. These may address different things. Ask Monerium. [Conflict, unresolved]
- So **"everyone pays into one organiser's personal IBAN" should not be the design.**

## 5. Off-ramp from a Safe

### Model A (recommended): pay out, then the person cashes out
- Proposal: ordinary ERC-20 transfer, Safe to recipient's own wallet. Signers can recognise the destination, a known member address.
- Recipient redeems in monerium.app with their own wallet signature. Only one signer involved; no timing coupling. ToS §8.5: moving e-money to another address transfers the redemption right to that holder. [V]
- Personal third-party payouts of EUR 15,000 or more need a supporting document. [V] Own-account payouts: optional. [V]

### Model B: Safe redeems directly at Monerium (legal-entity groups, later)
- Order message: `Send EUR {amount} to {IBAN} at {timestamp}`. Timestamp "within 5 minutes of the current time or any time in the future". [V] So set a future timestamp to allow time for signature collection. [inference]
- Signature options: off-chain combined signatures, or on-chain. `GET /signatures` lists pending items. [V]
- Maps to a Safe **message signing** proposal (or a `signMessage` transaction), not a token transfer. The approval UI must show amount, IBAN and timestamp in plain words. Requires OAuth or Private plan; the Private plan covers "your own wallet, IBAN and orders" only. [V] Untested with a real Safe.

### Model C: provider deposit address (avoid for multisig)
Proposal is an ERC-20 transfer to an address supplied by a provider session.

| Risk | Evidence | Mitigation |
|---|---|---|
| Address expiry | MoonPay: deposit must arrive within 48 hours or `Deposit timeout`. [V] Mt Pelerin: no deadline stated, rate fixed on receipt. [V] Others [U]. | Proposal expiry shorter than provider window; visible countdown. Multisig approval times regularly exceed this. |
| Price or amount drift | Mt Pelerin rate set on receipt [V]; Ramp warns quote can change. [V] | Show estimates only. Exact-amount requirements [U]. |
| Sender matching | Mt Pelerin matches by **sending address and chain**, so the Safe must be the verified address on that one account. [V] | Effectively one account per Safe. |
| Memo | EVM deposits: no memo documented at Mt Pelerin. [V] Monerium `memo` is a SEPA reference only. [V] | Never rely on memos. |
| Refund destination | MoonPay `refundWalletAddress` requires signing. [V] Mt Pelerin: "Crypto assets are not refundable"; failed transactions "will not be automatically rolled back". [V] | Assume refund goes to origin at best, or support case. |
| Wrong network | Mt Pelerin: will not match automatically; contact support. [V] Bitvavo: may be lost, or recovery fee. [V] | Lock chain in UI; refuse if the Safe's chain differs. |
| **Signer cannot verify the address** | Inference: a malicious proposer can label any address "provider deposit". No public allowlist exists. | Strongest reason for Model A. If C is ever used, require out-of-band checking. |

Payouts from Mt Pelerin must go to a bank account in the user's own name, unless using a personal IBAN. [2: FAQ summary]

A future option worth noting: Bridge's liquidation addresses are static with no expiry, but need a developer contract and customer onboarding. Against the "no payment infrastructure" goal for now.

## 6. Frame and status checks

Live `curl` on 2026-11-08 with a browser user agent. Bot protection may vary headers. [V]

| URL | Status | X-Frame-Options | frame-ancestors | Embeddable from FundTogether? |
|---|---|---|---|---|
| widget.mtpelerin.com | 200 | none | no CSP at all | Yes by headers; needs origin-bound key [S] |
| monerium.app, sandbox.monerium.dev | 200 | none | self, app.safe.global, ambire, walletconnect, coinshift, `http://localhost:5173`, idos demo, safe.linea | **No** |
| global.transak.com, global-stg | 200 | none | CSP without frame-ancestors | Yes by headers; needs session URL |
| app.rampnetwork.com (with params) | 200 | none | none | Yes by headers; SDK embedded mode. Bare URL redirects to marketing site. |
| app.dev.ramp-network.org | 200 | none | none | Test environment |
| buy.moonpay.com, sell.moonpay.com (no key) | 200 | none | `https://*.moonpay.com` | No |
| buy.moonpay.com (`pk_test_123`) | 200 | none | `*` | Docs: production needs domain allowlist |
| exchange.mercuryo.io | 200 | none | CSP without frame-ancestors | By headers; signature required |
| sandbox-exchange.mrcr.io | 403 | | | IP-whitelisted |
| checkout.banxa.com | 403 | SAMEORIGIN | | Inconclusive (curl blocked) |
| pay.coinbase.com | 200 | DENY | self + checkout.com + keys.coinbase | **No**; docs agree |
| app.peer.xyz, peer.xyz | 200 | DENY | `'none'` | No |
| swap.cow.fi | 200 | none | `*` | Yes |
| bitvavo.com, app.safe.global, request.network | 200 | SAMEORIGIN | | No |
| peanut.me, bridge.xyz | 200 | SAMEORIGIN | `'self'` | No |

### CSP FundTogether needs

`config/initializers/content_security_policy.rb` is fully commented out, so **no CSP is sent today** and nothing blocks anything. Recommended link-out needs **no CSP change**.

Only if an iframe is added later:

```ruby
policy.frame_src :self, "https://widget.mtpelerin.com"
# plus only for the popup script variant:
# policy.script_src :self, "https://widget.mtpelerin.com"
```
```html
<iframe allow="usb; ethereum; clipboard-write; payment; microphone; camera"
        src="https://widget.mtpelerin.com/?_ctkn=KEY&..."
        title="Mt Pelerin crypto exchange widget"></iframe>
```
If a `Permissions-Policy` header is added, it must delegate camera and microphone or provider KYC breaks. [V: MoonPay FAQ and Mt Pelerin docs]

## 7. Regulatory exposure (flags only)

Authority note: **the AFM, not DNB, licenses CASPs in the Netherlands**; DNB handles prudential supervision. [2: DNB page via search; AFM page confirms licence duty] MiCA Art. 143(3) grandfathering ended 1 July 2026. [V: ESMA page]

| Option | Exposure | Advice |
|---|---|---|
| **Plain neutral link, member initiates, no payment from provider** | Lowest. Still a recommendation. Under Art. 61, solicitation "regardless of the means of communication", including "through an entity acting on its behalf"; brand advertising counts; ESMA: "very narrowly framed". [V: ESMA35-1872330276-1899] | Prefer providers in the EU register. If listing Mt Pelerin, state its status; do not promote. Have counsel review. |
| **Embedding widget** | More: looks like part of our service; involves an integration agreement; KYC/camera flows on our domain; users may think we run it. | Avoid. |
| **Revenue share or partner fee** (Mt Pelerin 25%, Transak, CoW) | Highest: commercial link strengthens "acting on its behalf", may look like reception and transmission of orders or placing; a fee conflict needing disclosure. | **Do not take any**, matching the brief. |
| **Monerium OAuth** | Formal partner agreement; operator handles tokens server-side and places orders on behalf of users; API terms bar resale. [V] | Later only. Ask Monerium whether group use is acceptable. |
| **Monerium Whitelabel** | Reliance route says "you hold the appropriate licences". [V] | Never. |
| **Custody and pooling** | If FundTogether ever holds a signer key or moves funds unilaterally, possible custody/transfer service and payment service issues. Pooling money for a third party may raise crowdfunding, Wwft, tax or association-law questions. Mt Pelerin will not onboard businesses in unregulated "crowdfunding, escrow" activities. [V] | Keep non-custodial; have counsel check. |

Also: do not pass name, email or phone into provider URLs (privacy), and use `rel="noopener noreferrer"`.

## 8. Recommendation

| Direction | Primary | Fallback (no credentials) | Fallback (credentials) |
|---|---|---|---|
| **On-ramp** | Monerium link-out to member wallet, then contribute | Mt Pelerin direct link to member wallet, after legal review. Or user's own exchange if it supports that token and network (not Bitvavo). | Ramp hosted link, if chain is Base, Arbitrum or Polygon; Monerium OAuth |
| **Off-ramp** | Safe payout to member wallet, then Monerium redeem | Same payout, then Mt Pelerin direct link sell (min CHF 50) after legal review | Ramp sell; Monerium Safe-level redeem for legal entities |

### Integration shape: deep link, no iframe, no OAuth for launch

**Monerium:** `https://monerium.app/` with app-side instructions. No deep-link params documented. Display the exact chain and the member's address for them to link. Do not assume a return callback; detect arrival by watching the wallet balance.

**Mt Pelerin buy:**
```
https://widget.mtpelerin.com/?_ctkn=954139b2-ef3e-4914-82ea-33192d3f43d3&type=direct-link&lang=en&tabs=buy,sell&tab=buy&nets=base_mainnet&net=base_mainnet&dnet=base_mainnet&curs=EUR&bsc=EUR&crys=EURC&bdc=EURC&bsa=100
```
**Mt Pelerin sell:**
```
https://widget.mtpelerin.com/?_ctkn=954139b2-ef3e-4914-82ea-33192d3f43d3&type=direct-link&lang=en&tabs=buy,sell&tab=sell&nets=base_mainnet&net=base_mainnet&snet=base_mainnet&curs=EUR&sdc=EUR&crys=EURC&ssc=EURC&ssa=100
```
Notes:
- `lang` accepts en, fr, de, it, es, pt: **no `nl`**. [V] Default to `en`, and warn Dutch users.
- `net`/`dnet`/`snet` values: `xdai_mainnet`, `base_mainnet`, `arbitrum_mainnet`, `matic_mainnet`. For Gnosis use USDC, since EURC is not available there.
- `addr`/`code`/`hash`/`chain` are documented as a set for automated proof. Do not pre-fill for launch; the member signs in the widget. Behaviour of `addr` alone [U].
- URL-encode all values, especially `hash`. [V]

**Ramp, if a key is obtained:**
```
https://app.rampnetwork.com/?hostAppName=FundTogether&hostLogoUrl=<url>&hostApiKey=<key>&enabledFlows=ONRAMP&enabledCryptoAssets=BASE_USDC&inAsset=EUR&inAssetValue=100&userAddress=<memberWallet>
```
Parameter semantics mostly [V]; `inAssetValue` semantics and whether no-key hosted use functions [U].

**Monerium OAuth, if later:** `https://api.monerium.app/auth?client_id=&code_challenge=&code_challenge_method=S256&redirect_uri=&state=`, sandbox host `api.monerium.dev` with `skip_kyc`. Then `POST /addresses`, `POST /ibans` once profile is `approved`, `POST /orders`. Requires a backend and server-side tokens. [V]

### What the UI must disclose before the link
- Who the provider is, its regulator and country, and that FundTogether is not the provider, does not hold funds and earns nothing.
- Exact fee as of a stated date, with a link to the provider's page. Use wording like "provider shows the final price" where numbers are unverified. **Do not print "free" for Monerium until confirmed.**
- Mt Pelerin specifically: free only on the first 500 per calendar year, and the bracket applies to the whole transaction; **7-day hold** for unverified SEPA buys; CHF 999 per 30 days; CHF 20 possible refund fee; not found in the ESMA register as of the check date.
- Currency: EURe or EURC is not a bank deposit; USDC adds EUR/USD risk.
- Network: exact name and token; wrong-network loss warning; need for gas.
- KYC: documents required (Monerium: ID, selfie, proof of address), performed by provider.
- That funds reach **your own wallet first**, and a second step moves them to the group, which needs its own transaction.
- For cash-out: the recipient, not the group, is the account holder; possible tax and third-party questions.

### What requires production credentials from the user

| Item | Needed for launch? | What the user does |
|---|---|---|
| Monerium link-out | **No** | Nothing. |
| Mt Pelerin direct link | **No** [S, confirm in browser] | Legal review only. |
| Mt Pelerin iframe | No | Email a live URL for a key; KYB and agreement for card. |
| Ramp key | Optional | Web form; separate enablement for off-ramp. |
| Monerium OAuth | Optional | Partner application, meeting, agreement, production app. |
| Transak, MoonPay, Coinbase, Mercuryo, Banxa, Bridge | Not recommended | KYB, contracts, backends. |

### Testing without credentials

| Test | How | Honest label |
|---|---|---|
| URL builder | Unit tests on params per chain; no network. | Automated |
| Link liveness | HTTP HEAD in a manual check, not in CI. | Automated |
| Mt Pelerin UI | Open direct link or localhost key on `:3000`; stop before paying. | Real service, no transaction. Not a sandbox. |
| Contribution and payout flow | Testnet token in a testnet Safe, with no provider. | Simulated; proves our app, not the ramp. |
| Monerium sandbox | User creates free sandbox login at sandbox.monerium.dev; `skip_kyc`; "Simulate bank transfer" on Receive page mints test EURe; chains include Chiado, Amoy, Sepolia, Arbitrum Sepolia, Base Sepolia. [V] Simulated SEPA-out not documented. | Needs a sandbox client ID; no real KYC. |
| Others | Transak staging (dummy KYC always approved, US examples; needs dashboard account and IP whitelist). MoonPay sandbox (test key from dashboard; can skip documents; Sepolia only). Ramp test env at app.dev.ramp-network.org (min EUR 0.05; test networks listed are partly stale). | Require accounts; not for launch. |

**Real-world test that goes live honestly:** one consenting person with real KYC at Monerium sends about EUR 1 by SEPA Instant, receives EURe, contributes to a real Safe, group approves a payout proposal, recipient redeems about EUR 0.50 to their bank. Real money, real KYC, low amount, no contract. Agents must not perform this. Do not pick Mt Pelerin for a fast test: the 7-day hold on unverified SEPA makes it slow.

## 9. Open items to confirm

1. Monerium's current fees and whether multiple profiles can link one address (ask Monerium). Also whether pooled-group use needs written approval.
2. Mt Pelerin direct link in a real browser from our domain, and its EU legal basis. Ask them.
3. EURe contract addresses and liquidity on the selected chain (chain agent).
4. Lawyer: link-only exposure, Art. 61, Wwft, pooling.
5. Ramp no-key behaviour; contract-address delivery at Ramp, Transak, MoonPay.
6. Bitvavo help pages were blocked by a bot check; Travel Rule details are from snippets.

## Sources

- Mt Pelerin: https://developers.mtpelerin.com/llms-full.txt, https://www.mtpelerin.com/terms-conditions, https://www.mtpelerin.com/faq/how-to-sell-cryptocurrency, https://widget.mtpelerin.com/js/app~748942c6.e7afd0af.js, https://api.mtpelerin.com/currencies/tokens, https://api.mtpelerin.com/currency_rates/sellLimits/EUR
- Monerium: https://docs.monerium.com/faq, /oauth, /whitelabel, /private, /sandbox, /api, /kyc-guide-individuals, https://monerium.com/partners/, https://monerium.com/policies/personal-terms-of-service/, https://monerium.com/policies/api-terms-of-service/
- Transak: https://docs.transak.com/integration/web/website-redirection.md, /integration/web/iframe.md, /guides/mandatory-security-changes.md, /guides/sandbox-credentials.md, /customization/query-parameters.md, /api/public/verify-wallet-address.md
- Ramp: https://docs.rampnetwork.com/api-keys, /configuration, /off-ramp, /testing-environment, https://support.rampnetwork.com/en/articles/10415-what-fees-are-charged-when-buying-crypto, https://support.ramp.network/en/articles/8957-what-are-the-fees-for-selling-crypto-at-ramp
- MoonPay: https://dev.moonpay.com/widget/faqs.md, /widget/on-ramp/customization/url-signing.md, /widget/on-ramp/customization/ip-matching.md, /widget/off-ramp/overview.md, /widget/sandbox-testing.md, https://www.moonpay.com/en-ca/legal/pricing_disclosure, https://support.moonpay.com/en/articles/727279-virtual-accounts-processing-times-fees-and-limits
- Coinbase: https://docs.cdp.coinbase.com/onramp/additional-resources/faq
- Stripe: https://docs.stripe.com/crypto/onramp, https://docs.stripe.com/crypto/onramp/stripe-hosted.md
- Banxa: https://docs.banxa.com/products/hosted-checkout/api-guide.md. Mercuryo: https://widget.docs.mercuryo.io/guide/more/faq, /guide/integration/security
- Bridge: https://apidocs.bridge.xyz/get-started/guides/move-money/eur-integration-guide.md
- Bitvavo: https://bitvavo.com/en/fees, https://api.bitvavo.com/v2/assets, https://support.bitvavo.com/hc/en-us/articles/30237732801553
- Peer: https://docs.peer.xyz/guides/for-buyers/tiers. Request: https://docs.request.network/api-features/crypto-to-fiat-payments.md. CoW: https://docs.cow.fi/governance/fees/partner-fee. Safe: https://help.safe.global/articles/8213909172-how-to-buy-cryptocurrency-on-ios
- Regulation: https://www.esma.europa.eu/esmas-activities/digital-finance-and-innovation/markets-crypto-assets-regulation-mica, https://www.esma.europa.eu/sites/default/files/2024-12/CASPS.csv, .../NCASP.csv, .../EMTWP.csv, ESMA35-1872330276-1899 reverse solicitation report, https://www.afm.nl/nl-nl/sector/cryptopartijen, https://www.dnb.nl/voor-de-sector/open-boek-toezicht/sectoren/aanbieders-cryptodiensten/

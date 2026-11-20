# Ramps: getting money in and out of a fund

**No ramp has been used with real money.** No account was created, no KYC was submitted and no sandbox was
used. What is tested is URL construction and our own pages, nothing beyond that.

Evidence: `docs/research/on-off-ramps.md` and `docs/research/chains-and-tokens.md`, checked 2026-11-08.
This is not legal advice. The regulatory points are flags for a lawyer.

## Code

| Part | Where |
|---|---|
| Providers, routes, gas, faucet | `config/ramps.yml`, read only by `Ramps::Catalog` |
| What one fund may see | `Ramps::FundGuide` |
| Pages | `RampsController`, `app/views/ramps/`, `account_ramp_path`, `leave_account_ramp_path` |
| Link check | `bin/rails ramps:check`, `Ramps::LinkCheck` |
| Tests | `test/services/ramps/catalog_test.rb`, `test/integration/ramps_test.rb` |

Fixed rules: no embedding, no iframes, no revenue-share parameters, no credentials, no personal data in a provider
URL, and no provider deposit address in a multisig proposal. `config/ramps.yml` contains no on-chain address at all,
and a test holds it to that.

## What each flow does

A viewer can read every page but gets no actions. A member or admin gets the actions. Anyone else gets a 404.
A fund only sees routes for its own chain and token.

**Geld erin (on-ramp):**

1. Shows the member's own linked wallets. This reads our database, not the browser wallet.
2. Buy into that wallet, never into the Safe. A provider link goes through an interstitial (`/ramp/leave?route=`) that
   says you leave FundTogether, the provider handles KYC and funds, and FundTogether holds nothing and takes no fee.
   The link opens a new tab with `rel="noopener noreferrer"`. The route id is resolved within the fund's own chain
   and token, so the page cannot link elsewhere. The own-exchange route gives instructions only, with no link.
3. Explains gas: which token, a dated rough amount that is not a live price, and where to get it.
4. Contribute, as a separate transaction from the wallet. Without an active Safe the page warns against sending.

**Geld eruit (off-ramp):**

1. A payout proposal to the member's own linked wallet. The page only ever pre-fills that wallet.
2. Explains approvals. The threshold shown is the one chosen at creation and is labelled as such. The proposal shows
   the live state.
3. Explains gas.
4. Redeem at a provider, from the member's own wallet, to their own bank account.

The page states that the recipient receives the euros, not the fund, and flags tax and record-keeping as non-advice.

**Empty states:** no chain yet, chain not enabled on this server, or a token not in the registry each give an explanation
and no routes. **Testnet:** the page says real ramps do not apply and that this is test money, and explains the Circle
faucet (EURC, Ethereum Sepolia).

## Routes by fund

| Fund | Geld erin | Geld eruit |
|---|---|---|
| Sepolia + EURC | Circle faucet, test money | Payout only, nothing to redeem |
| Gnosis + EURe | Monerium | Monerium |
| Base + EURC | Own exchange (instructions) | Own exchange (instructions), Circle's redemption policy |
| Base + EURC, flag on | Above plus Mt Pelerin | Above plus Mt Pelerin |

**Open decision: Base + EURC has no Monerium route.** The Decisions table in `docs/ARCHITECTURE.md` names Monerium as the
on-ramp, but Monerium issues EURe, not EURC, and the registry gives Base only EURC. With Mt Pelerin off, a Base fund has
no provider on-ramp, only an own-exchange route resting on Coinbase's public API, unconfirmed for Dutch retail. Gnosis +
EURe, or adding EURe on Base (supply was only 26.6k, no DEX liquidity found), are the alternatives. Decide before
enabling a mainnet.

**Mt Pelerin** is off everywhere unless `FUNDTOGETHER_ENABLE_MTPELERIN=1` exactly. Set it only after legal review. When on,
its legal status appears on the page and on the interstitial. It offers xDAI on Gnosis, but the catalog does not name
it as a gas source.

## Tested

- Catalog rules: sources and dates on every entry, no free claim on unconfirmed fees, no addresses, no revenue-share
  parameters, the Mt Pelerin flag.
- Integration: roles, routes per chain, empty states, disclosures, link attributes, payout pre-fill.
- Real headless Chrome under the strict CSP, at 1280 px and 390 px: all pages, no violations, no horizontal overflow.
- `ramps:check` was run once by hand. A 200 only says a host answered.

## Not tested

- Any real-money round trip, in either direction, at any provider.
- KYC at any provider, and any provider's sandbox.
- Whether a provider link works past its first page. Nobody clicked through the Mt Pelerin widget, and a refusal later in
  the flow is possible.
- Whether Coinbase offers EURC on Base to Dutch customers, or accepts it as a deposit.
- Monerium's current fees, limits and whether pooled-group use needs its written approval.
- Fees and limits may have changed since the check date. Nothing updates them automatically.

## What a person must do

**Everyone:** rerun `bin/rails ramps:check`, then re-read fee and limit pages and update `verified_on` in
`config/ramps.yml`. A lawyer reviews link-only exposure (MiCA Art. 61), Wwft and pooling.

**Monerium, real money:** one consenting person with real KYC sends about EUR 1 by SEPA Instant, receives EURe on Gnosis,
contributes to a real Safe, the group approves a payout, and the recipient redeems about EUR 0.50 to their own bank.
Also ask Monerium about fees and group use. Agents must not do this.

**Mt Pelerin:** get legal sign-off first. Then open the direct link in a real browser and stop before paying. It has no
sandbox, so this is the real service. Do not choose it for a quick test: unverified SEPA buys are held 7 days.

**Own exchange:** with a real account, confirm EURC can be withdrawn and deposited on Base, with a small amount.

**Circle:** read the current policy and walk through the holder registration.

**Circle faucet:** request EURC on Ethereum Sepolia and confirm the amount, which the page did not state.

## Monerium sandbox plan

No credentials are needed for the live link-out. This plan tests the flow without real money:

1. A person creates a free login at `https://sandbox.monerium.dev`. `skip_kyc` applies there, so there is no real KYC.
2. Link a throwaway test wallet on Sepolia, which matches our testnet. Sandbox EURe on Sepolia differs from the
   fund's Circle EURC, so a test fund for this needs a sandbox-token registry entry first.
3. Use "Simulate bank transfer" on the Receive page to mint test EURe.
4. Contribute to a test Safe, approve a payout, and execute it.
5. Try the redeem. Simulated SEPA-out is not documented, so record what actually happens.

Label the result simulated. It proves our flow and Monerium's sandbox, not production.

## Credentials for optional integrations

None is needed today.

| Integration | Needed | Who |
|---|---|---|
| Monerium sandbox via API | Sandbox client ID | Person, on sandbox.monerium.dev |
| Monerium OAuth | Partner application, meeting, agreement, production app, backend tokens | Operator, with legal review |
| Mt Pelerin iframe | Not planned. Production key after emailing a live URL; KYB and agreement for card | Operator |
| Ramp hosted link | `hostApiKey` by web form; separate enablement for off-ramp | Operator |
| Transak, MoonPay, Coinbase Onramp, Mercuryo, Banxa, Bridge | KYB, contracts, backends. Not recommended | Operator |

## Link check

`bin/rails ramps:check` sends HTTP HEAD to each URL in the catalog and prints only the status. It is not part of tests or CI.
Bot protection can answer 403 or 405 to a page that works in a browser, and a 200 does not prove a flow works.

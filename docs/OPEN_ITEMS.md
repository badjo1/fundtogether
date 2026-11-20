# Open items before real money

FundTogether is ready for real-world testing on **Sepolia**. Everything below must be done before
enabling a mainnet (`FUNDTOGETHER_CHAINS=gnosis` or `base`). Status as of 2026-11-11.

## Requires a person (cannot be automated here)

- [ ] **Real wallets.** All live tests signed with an injected test wallet. Test with Rabby and
  MetaMask (desktop extension), MetaMask and Rabby mobile in-app browsers, at least one hardware
  wallet (Ledger or Trezor), Safari and Firefox. Check that each wallet displays the EIP-712 Safe
  transaction readably and that the safeTxHash matches the one on the proposal page.
- [ ] **Phones.** QR handoff to a wallet's in-app browser, wallet linking and signing on iOS and
  Android.
- [ ] **Safe{Wallet} exit drill.** Open a test fund in app.safe.global, check owners, threshold and
  balance, and execute a payout there without FundTogether. Only the link format, the Safe
  Transaction Service's view of the Safe, and a script-based exit (journey G) are proven so far.
- [ ] **Accessibility.** Screen reader and keyboard pass over the signing and contribute flows.

## Legal and compliance (needs a lawyer)

- [ ] MiCA, AFM and DNB: whether linking to ramp providers from the app is allowed, and whether
  operating a group-pooling app has licensing or Wwft implications in the Netherlands.
- [ ] Monerium: whether its terms allow group use. Its ToS restrict acting for third parties.
- [ ] Mt Pelerin: its own page says it has no EU MiCA authorisation and does not solicit EU
  clients. It stays off (`FUNDTOGETHER_ENABLE_MTPELERIN`) until cleared.
- [ ] WalletConnect: Reown's licence for `@walletconnect/ethereum-provider` 2.21.9 and later needs a
  commercial agreement above 500 monthly users. WalletConnect is not included; decide before
  adding it.
- [ ] Privacy policy and terms of use: wallet addresses are public on-chain and linked to accounts
  in our database.

## Audits and security

- [ ] **External security audit** of the signing path: `app/javascript/safe/`, `app/services/chain/`
  (EIP-712, signature recovery, policy, proposal builder, deployment verifier). The Safe contracts
  themselves are audited; this application code is not.
- [ ] **Residual risk H5** (tampered JavaScript delivery, the Bybit pattern) cannot be closed by the
  app. Recommend hardware wallets and out-of-band safeTxHash checks for any fund with meaningful
  value. See `docs/SECURITY_REVIEW.md`.
- [ ] **Medium-risk items mitigated, not closed:** M1 (the browser can't verify that the owners are
  the right people) and M14 (rate limits depend on correct `TRUSTED_PROXIES` behind the real proxy).
- [ ] Re-run `bin/bundler-audit update && bin/bundler-audit` and `bin/importmap audit` before each
  release. The vendored viem bundle is not covered by `importmap audit`; track viem advisories
  manually (`docs/VENDORED_JS.md`).

## Production deployment

- [ ] Host, TLS and a reverse proxy that redirects HTTP to HTTPS (L7 in the security review).
- [ ] Environment: `APP_HOST` (required), `RESEND_API_KEY` or other SMTP, `TRUSTED_PROXIES`,
  `ALLOWED_HOSTS` if needed. See README.
- [ ] Production PostgreSQL with the primary, cache, queue and cable databases.
- [ ] Docker image build: the Dockerfile moved to Ruby 3.4.10 and sets `SOLID_QUEUE_IN_PUMA`; a
  Docker build and production boot in a container have **not** been tested. Production mode was
  verified locally only.
- [ ] Real email delivery (only `letter_opener` was used).
- [ ] RPC: public endpoints work but rate-limit `eth_getLogs`. For production volume, add a keyed
  endpoint per chain via `FUNDTOGETHER_RPC_URLS_<CHAIN>`. This is the only server secret for chains.
- [ ] Monitoring for the chain sync job and RPC errors, plus database backups.

## Product decisions still open

- [ ] **Mainnet choice.** Recommendation changed during the work: **Gnosis + EURe** is now preferred
  over Base + EURC, because Monerium (the only credential-free euro on-ramp the app can link to)
  issues EURe and has no route to EURC on Base. Gnosis also has faster finality. Its weak point is
  gas: major exchanges do not list xDAI. Both chains are configured and verified read-only in
  `config/chains.yml`; neither has been used with real money.
- [ ] **Gas.** Users pay gas themselves. A member holding only euro tokens can't transact. A
  sponsoring relayer would need a server key and legal review; not built.
- [ ] **Contract-wallet owners** (Safe as owner, smart wallets) are refused in v1.
- [ ] **Ramps:** no flow has been used with real money. A first real test is one consenting person
  doing about €1 via SEPA through Monerium on Gnosis: buy, contribute, payout, redeem
  (`docs/RAMPS.md`). Fee and limit texts were verified on 2026-11-08 and must be rechecked.
- [ ] Not built: Safe Transaction Service mirroring (pending proposals don't show in Safe{Wallet}),
  passkey or embedded wallets, notifications beyond email, a native mobile app.

## Not verifiable on a testnet

- Chain reorgs (handled in code and unit tests, never observed live).
- `ExecutionFailure` on a live Safe: unreachable with `safeTxGas = 0`, which reverts with GS013.

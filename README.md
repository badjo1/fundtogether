# FundTogether

Shared money, simple and transparent. A group creates a fund, members contribute any amount of a
euro stablecoin from their own wallet, and the money sits in a standard
[Safe](https://safe.global) multisig that only the group's signers can move. Payouts are proposals
that need a set number of approvals. Every balance, contribution and payout is read from the chain
and links to a block explorer.

FundTogether is non-custodial. The server holds no private keys and cannot move funds. If the app
disappears, each fund is still a normal Safe that its owners can operate in Safe{Wallet} or
directly on-chain.

**Status:** ready for real-world testing **on Sepolia testnet only**. Mainnet is switched off by
default and should stay off until the items in [docs/OPEN_ITEMS.md](docs/OPEN_ITEMS.md) are done.

## What works

Proven with real transactions on Sepolia in a real browser (see
[docs/TESTNET_EVIDENCE.md](docs/TESTNET_EVIDENCE.md)):

- Register with email confirmation, create several funds, invite members by email, link or QR.
- Link wallets with a signature (EIP-6963 browser wallets; phones via the wallet's own browser).
- Deploy a Safe 1.4.1 with chosen signers and threshold; the server verifies it on-chain.
- Contribute EURC or ETH; contributions are attributed from chain events only.
- Propose, approve and execute payouts; add, remove and swap signers; change the threshold;
  reject a proposal; recover from nonce conflicts.
- Activity with explorer links and CSV export; a transparency page per fund.
- Ramp guidance: link-outs to regulated providers, with fees, limits and KYC disclosed.

Signing in these tests used an injected test wallet. Real wallet extensions, phones and hardware
wallets have not been tested yet.

## Requirements

- Ruby 4.0.10 (see `.ruby-version`)
- PostgreSQL 14 or newer
- Node 20 is only needed to run the JavaScript tests and to rebuild the vendored viem bundle; it
  is not needed to run the app.

## Setup

```sh
bundle install
bin/rails db:prepare
bin/dev            # web + Tailwind watcher; default port 3000, or PORT=3001 bin/dev
```

Open the app, register, and confirm your email: in development, mail opens in the browser via
`letter_opener`. Background jobs (chain sync) run inside Puma in development when
`SOLID_QUEUE_IN_DEV=1`, or separately with `bin/jobs`.

To try the on-chain flows locally you need a browser wallet (Rabby or MetaMask) on **Sepolia**
with a little Sepolia ETH for gas and test EURC from [faucet.circle.com](https://faucet.circle.com)
(EURC, Ethereum Sepolia). Use a test wallet, never one holding real funds.

## Tests

```sh
bin/rails test                         # Ruby: unit, integration, authorization (no network)
(cd test/javascript && node --test)    # JavaScript: wallet, Safe hashing, policy (no network)
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

`test/e2e/` is a live Sepolia end-to-end harness that spends test ETH. It is excluded from CI and
from `bin/rails test`; see the header of `test/e2e/run.mjs` and `test/e2e/serve.sh`.

## Configuration

| Variable | Where | Purpose |
|---|---|---|
| `APP_HOST` | production, **required** | Public host name. Mail links and the wallet sign-in domain use it; boot fails without it. |
| `ALLOWED_HOSTS` | production, optional | Extra comma-separated host names to answer to. |
| `TRUSTED_PROXIES` | production, optional | Proxy IPs/ranges, so rate limits see the real client IP. |
| `RESEND_API_KEY` | production | SMTP password for mail (see `docs/EMAIL_SETUP.md`). |
| `FUNDTOGETHER_CHAINS` | all | Enabled chains, comma separated. Default `sepolia`. Mainnets (`gnosis`, `base`) only when explicitly listed. |
| `FUNDTOGETHER_RPC_URLS_<CHAIN>` | server only | Extra RPC endpoints (may contain keys); never sent to browsers. |
| `FUNDTOGETHER_ORIGIN` | development, optional | Origin used in wallet-link messages when not on localhost:3000. |
| `FUNDTOGETHER_ENABLE_MTPELERIN` | optional | `1` shows Mt Pelerin links. Keep off until legal review. |
| `SOLID_QUEUE_IN_PUMA` | production | Runs jobs in the web process (set in the Dockerfile). |
| `SOLID_QUEUE_IN_DEV` | development | Same, for `bin/dev`. |

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): technical overview, decisions, data model,
  proposal rules, threat model, browser/server contract.
- [docs/OPEN_ITEMS.md](docs/OPEN_ITEMS.md): what still needs credentials, audits, legal review or
  deployment work before real money.
- [docs/TESTNET_EVIDENCE.md](docs/TESTNET_EVIDENCE.md): every live test with transaction hashes.
- [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md): independent review and status per finding.
- [docs/RAMPS.md](docs/RAMPS.md): on- and off-ramp flows and what has been verified.
- [docs/FRONTEND_CONTRACT.md](docs/FRONTEND_CONTRACT.md), [docs/VENDORED_JS.md](docs/VENDORED_JS.md),
  [docs/STYLEGUIDE.md](docs/STYLEGUIDE.md).
- [docs/research/](docs/research/): the research behind the chain, Safe, wallet and ramp choices.

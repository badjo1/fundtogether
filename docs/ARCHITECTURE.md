# FundTogether architecture

The single source of truth for how FundTogether does on-chain money. If code and this
document disagree, one of them is a bug. Evidence and alternatives are in `docs/research/`.

## Principles

1. **Non-custodial.** The server holds no private keys, ever, and cannot move funds.
2. **The chain is the source of truth for money.** Postgres caches and annotates. A balance,
   contribution or execution is only shown as real if it came from chain data.
3. **No custom contracts.** Only canonical, audited Safe 1.4.1 and existing stablecoins.
4. **No proprietary token, no fees taken by FundTogether, no revenue share.**
5. **Exit hatch.** Every fund is a standard Safe that its owners can operate in Safe{Wallet}
   or directly on-chain if FundTogether disappears.
6. **Nothing faked.** A flow not proven on a live network is labelled untested, not working.

## Decisions

| Topic | Decision | Why (see docs/research) |
|---|---|---|
| Multisig | Safe L2 1.4.1, direct calls with viem, signatures in Postgres | API Kit needs a key a browser cannot hold; Protocol Kit is heavy and needs polyfills |
| Deployment | `createProxyWithNonce` | Default in Safe tooling, so Safe{Wallet} compatibility |
| Transaction Service | Not used in v1 | Keyless quota (2 RPS, 5,000/month) is not a production budget |
| Wallets | Own EIP-6963 + EIP-1193 layer, no framework | Smallest surface; AppKit has the largest graph and widest CSP |
| Mobile | Open the app in the wallet's in-app browser via QR/deep link and single-use handoff token | No relay. WalletConnect is optional, off unless configured, and has an open licence question |
| Wallet linking | SIWE-style signature links wallets. Not a login method | Email + password stays the login |
| Owners in v1 | EOAs only | Contract owners would need `approveHash`, unproven here |
| Ruby crypto | `keccak` + `ecdsa` gems, verified locally | `eth` needs `rbsecp256k1`, which failed to build here and needs automake/libtool. An RPC precompile would mean trusting the RPC for identity |
| Testnet | Sepolia, with Circle EURC | Canonical Safe present. Chiado has none |
| Mainnet | Off by default. Registry holds Gnosis + EURe (recommended) and Base + EURC | See chain trade-off below. Enabling needs an explicit environment variable. Gnosis is recommended because Monerium, the only credential-free euro on-ramp, issues EURe and offers no EURC route on Base |
| Gas | Paid by the user in the wallet. No relayer | A server relayer means a server key, paid infra and a legal question |
| On-ramp | Link out to Monerium; neutral instructions for own exchange. Member buys to own wallet, then contributes | No credentials; no provider handles a multisig address |
| Off-ramp | Safe proposal pays the member's own wallet; member redeems with the provider | No provider deposit address inside a multisig proposal |
| Mt Pelerin | Not linked in production without legal sign-off (flag, default off) | Its own page says no EU MiCA authorisation and no soliciting EU clients |
| Monerium IBAN on a fund Safe | Not offered | Trust cost of its system role; ToS on third parties; needs legal review |
| CSS | Compiled Tailwind v4 with `@theme` parity; CDN script removed | Third-party script on a signing page is unacceptable |
| CSP | Strict, per-request `SecureRandom` nonce. `connect-src` is `'self'` plus the origins of `Chain::Registry.public_rpc_origins`: public RPC endpoints of enabled chains only, read per request | Limits injected script and where a page can talk to. Does not stop tampered same-origin delivery |

### Chain trade-off

Gas does not decide this: under 1.5 cents per action on Base and Gnosis.

- **Base + EURC:** more euro routes, far deeper euro-token supply on Base (EURC 52.3M, EURe
  26.6k), gas token (ETH) sold everywhere. About 16 min to finality, more centralised sequencer.
- **Gnosis + EURe:** 3.2 min finality, best public RPC, strongest with Monerium (13.9M EURe).
  Coinbase, Bitvavo and Kraken list neither EURe nor xDAI, so getting gas is harder.

Each fund stores `chain_id` and `token_address`, immutable after deployment, so this is
configuration, not architecture.

## Fund lifecycle

`accounts` remains the fund table. Dutch UI copy remains.

```
draft -> deploying -> active
```

- **draft:** name, purpose and members exist; no money possible.
- **deploying:** creator's wallet sent `createProxyWithNonce`; `deploy_tx_hash` recorded.
- **active:** the server has independently verified, from the chain, all of: code exists at
  the predicted CREATE2 address, singleton (storage slot 0) is the canonical SafeL2,
  `getOwners`/`getThreshold` match, no modules, no guard, canonical fallback handler.

"Create2 call failed" means someone may have deployed the identical Safe: verify, then treat
as success. Identical initializer is part of the salt, so front-running cannot change owners.

Threshold rules enforced client and server: at least 1, at most owner count. n-of-n with n > 1
and 1-of-n with n > 1 need an explicit acknowledgement (lockout risk; single-signer control).

Owners are active verified wallets of active members with the `member` or `admin` role (a viewer cannot
sign), at most one per person, stored in ascending numeric order. Salt:
`uint256(keccak256("fundtogether.safe.v1" ++ safe_group_uuid ++ uint256(chain_id) ++ uint256(0)))`. The nonce
is not required to be 0 at verification: an identical Safe already in use is checked on its current state. A
reverted deploy transaction with no Safe at the address, or one not found after 24 hours, returns to draft.

Wallet linking refuses addresses with code on any enabled chain, except EIP-7702 delegated EOAs (`0xef0100...`),
which still sign with their own key. Unlinking is always allowed, even for a current owner, because a
compromised wallet must be removable from the account; the answer lists Safes it still owns.

## Data model (additive)

`numeric(78,0)` for all on-chain amounts. Addresses stored lowercase, without checksums.

- `accounts` add: `chain_id`, `token_address`, `safe_address` (unique per chain),
  `safe_salt_nonce`, `safe_status`, `deploy_tx_hash`, `synced_block`, `synced_at`; also `safe_group_uuid`
  (salt input), `safe_owners` + `safe_threshold` (the intent the initializer is built from),
  `synced_block_hash` (reorg detection at the cursor), `safe_verification_error`, `safe_verified_at`, and
  `balance_cached` + `balance_cached_at` (only for the labelled fallback under Chain sync).
- `wallets`: `user_id`, `address`, `kind` (`eoa`), `label`, `verified_at`, `revoked_at`. Partial
  unique index on `address` where not revoked.
- `wallet_challenges`: `user_id`, `session_id`, `nonce` (unique; for `handoff` the SHA-256 of the token),
  `purpose` (`link`, `handoff`), `address`, `chain_id`, `message` (the composed text; `link` only),
  `expires_at`, `consumed_at`.
- `safe_proposals`: `account_id`, `proposer_id`, `kind`, `title`, `params` (typed input, normalised), `to`,
  `value`, `data`, `operation`, `nonce`, `safe_tx_hash` (unique per account), `state` (`open`, `executed`,
  `failed`, `superseded`), `execution_tx_hash`, `executed_at`. Gas fields are not stored: always zero.
- `safe_signatures`: `safe_proposal_id`, `signer_address`, `signature`, `user_id`. Unique per
  proposal + signer.
- `chain_events`: `account_id`, `chain_id`, `tx_hash`, `log_index`, `block_number`, `block_hash`,
  `kind` (`token_in`, `token_out`, `native_in`, `execution_success`, `execution_failure`, `owner_added`,
  `owner_removed`, `threshold_changed`), `from_address`, `to_address`, `token_address`, `amount`, `safe_tx_hash`
  (execution events), `occurred_at`, `finalized`, `user_id` (matched by wallet), `safe_proposal_id`. Unique on
  `account_id, chain_id, tx_hash, log_index`: a transfer between two funds' Safes is one log and belongs to both.
- Removed: the self-reported ledger (`transactions` table, `account_memberships.balance_cents`,
  `accounts.split_method`, `accounts.wallet_address`, `users.wallet_address`). There is no production
  data to preserve, so none of it is migrated.

**Never store** "ready to execute", confirmed balances, or a signature count as truth. Those
are computed against live owners, threshold and nonce whenever needed. Lowering a threshold
makes older partial signature sets executable, so a cached flag is dangerous.

## Proposal rules

`kind`: `transfer_token`, `transfer_native`, `add_owner`, `remove_owner`, `swap_owner`,
`change_threshold`, `rejection`. The server builds `to`/`value`/`data` from typed parameters.
Clients never submit raw calldata. New owners follow the deployment rule above, and their account's email must be
confirmed (see Identity).

### Nonce and queue rules

A member without signing power must not be able to jam a fund (docs/SECURITY_REVIEW.md, H1). The design keeps the
queue in the hands of owners, keeps every escape route open, and bounds what anyone can leave lying around:

1. **Who claims which nonce.** A proposal by someone who is not a live owner always takes the Safe's current
   nonce. It competes there; it never pushes anyone back. An owner's proposal takes the lowest nonce from the current
   one upward that no *holding* proposal uses. A proposal holds its nonce if an owner proposed it or anyone has signed
   it. Unsigned junk holds nothing, so an owner's work goes in at the live nonce beside it.
2. **Owner changes are never blockable.** `add_owner`, `remove_owner`, `swap_owner` and `change_threshold` always take
   the current nonce, whoever proposes them, so nothing can sit in front of them. Two owner changes at one nonce
   exclude each other on-chain, which replaces the earlier "one open owner change" rule: that rule let a junk
   proposal block a real removal. The page warns about every sibling at the same nonce.
3. **Caps.** Open proposals at or above the live nonce: 5 per member who is not an owner, 10 per owner, 30 per fund
   for members who are not owners (`Chain::ProposalCreator`). An owner change or rejection from an owner or an
   admin is never refused by a cap. Refusals are `429 too_many_open_proposals` and `429 fund_queue_full`.
4. **Cancel.** `DELETE /accounts/:id/proposals/:id` (and the button on the page) withdraws a proposal inside the app:
   state `cancelled`, `cancelled_by`, `cancelled_at`. The proposer may cancel while nobody else has signed; an admin
   may always. It is off-chain only, and the page says so: signatures already given stay valid on the chain until
   that nonce passes, and the advice is to execute a rejection when that matters. An execution event for a cancelled
   proposal still wins in sync (the chain overrules the app). A cancelled row frees its `safe_tx_hash`, so the
   identical proposal can be made again.
5. **Departure.** Removing a member, or leaving a fund, cancels that person's open proposals.
6. **Gaps.** A cancel can leave a later proposal waiting for a nonce nothing fills. The page shows `nonce_gap` and
   offers "Opnieuw maken op het vrije volgnummer": the same content, cancelled and recreated at the free nonce.
   Signatures do not carry over, because the hash changes with the nonce.

Refused in both Ruby and JS, with a shared test vector file:

- `operation` != 0. MultiSendCallOnly is not used in v1.
- `safeTxGas`, `baseGas`, `gasPrice`, `gasToken`, `refundReceiver` non-zero.
- Self-calls other than the owner-management selectors. Explicitly including `enableModule`,
  `disableModule`, `setGuard`, `setFallbackHandler`, `changeMasterCopy`-style calls.
- Nonce below the Safe's current nonce.

Two open proposals may share a nonce: executing one makes the other `superseded`. An execution event in the logs is
enough to mark its siblings `superseded`; a lower chain nonce only reopens a superseded proposal when the same sync saw
a reorg by block hash, so a lagging endpoint cannot reopen anything. A rejection
is a zero-value self-call at the same nonce. `remove_owner`/`swap_owner` compute `prevOwner` from a
live `getOwners`, using the sentinel at the head.

Signing flow, each step in the user's browser:

1. Fetch proposal JSON.
2. Read `nonce`, `getOwners`, `getThreshold` from the chain.
3. Rebuild calldata from typed parameters and live owners; **refuse if it differs from the server's**.
4. Recompute `safeTxHash` locally; **refuse if it differs from the server's**.
5. Show decoded action, recipient, human amount, and hash for out-of-band checking.
6. `eth_signTypedData_v4`; POST signature.

Server on receipt: recompute the hash itself from stored fields, recover signer with local
crypto, require it to be a current owner (RPC read, advisory) and a verified wallet of the
current user. Signatures sorted ascending by owner at execution. High-s is refused, not normalised (a
malleated copy; wallets emit low-s). `v` 0/1 is normalised to 27/28 and stored that way; 31/32 is refused,
because FundTogether never uses `eth_sign`.

Execution is permissionless on-chain. After a tx, read the receipt: `ExecutionSuccess`/
`ExecutionFailure` decide state, not receipt status alone (inner failure with `safeTxGas > 0` emits
`ExecutionFailure` and burns the nonce). The client's claimed `tx_hash` is only a hint to sync: the execution
endpoint changes state only through an execution event in that receipt whose `safeTxHash` matches a proposal. It does
not read the chain nonce, because "the nonce moved" says nothing about which proposal moved it.

A payout the Safe cannot cover is never called ready: `live.reason` is `insufficient_balance` (or `balance_unknown`
when the balance could not be read), the execute panel is not shown, and the page offers cancel and rejection. The
browser checks the balance again before it sends, and refuses with `insufficient_fund_balance`.

Signature recovery runs once per row, at receipt (or the first read of an older row), and stores a keyed MAC over
hash, signer and signature. Every read still checks the signer against live owners and the stored MAC against the
recomputed hash; a row changed in the database fails the MAC and is recovered again. Closed proposals are not
recomputed at all. Lists show every open proposal (bounded by the caps) and pages of 25 closed ones; the JSON index
pages by 25. Live frames are limited to 60 per minute per user, the JSON index to 30.

## Chain sync

`Chain::LogSync` per active fund, via Solid Queue on a recurring schedule plus on demand after a
user tx. Ranges of at most 2,000 blocks, cursor in `synced_block`, at least two RPC endpoints per
chain, fallback on 429/5xx/range errors.

Events: token `Transfer` to/from the Safe; `SafeReceived`, `ExecutionSuccess`, `ExecutionFailure`,
`AddedOwner`, `RemovedOwner`, `ChangedThreshold`. Index the canonical token address only (EURe V1
events are ignored). Do not assume one log per transaction.

Unfinalized events display as "in behandeling" and are re-checked via `block_hash`, all blocks in one batched
request so a number of dust rows cannot become a number of requests; reorged rows are removed and the cursor rewinds. The cursor block's own hash is checked too, because a reorg can add logs
at heights with no stored row. Zero-value transfers (address poisoning) and self-transfers are not recorded.
Attribution uses the wallet active at the event's time, for active members of that fund who had joined by then.
Incoming amounts below 0,01 token or 0,00001 ETH from an unknown sender are collapsed behind a toggle on the activity
page and left off the dashboard; they stay in the data, the totals and the CSV. Unknown senders are shown in full and
checksummed, with a warning when they share the first and last four characters with a member's wallet. Contributions are from chain events only, whoever sent them; unknown senders
display as such and are never attributed by a client claim. Use the `finalized` tag, falling back
to `latest - chain.confirmations`.

Fund balance is `balanceOf` read live, with a clearly labelled timestamped fallback on RPC failure.
No figure silently shows zero when the RPC fails. The Safe's native balance is read too and shown next to it when it
is not zero. A native transfer emits no event of its own, so an executed payout's amount and recipient come from the
proposal whose `safeTxHash` the chain reported, labelled as such on the page and filled into the CSV.

Deployment: a claimed `deploy_tx_hash` moves a fund to `deploying` only if `eth_getTransactionByHash` finds it and its
target and input are exactly this fund's `createProxyWithNonce` call. A hash not found yet is ignored, not stored.
Verification of a deploying fund backs off (2, 4, 8 minutes up to an hour) and gives up after 30 attempts. Creating
funds is limited to 5 per hour per person.

## Authorization

Every fund route scopes through the user's active memberships. No unscoped `Account.find`.

| Action | viewer | member | admin |
|---|---|---|---|
| See fund, activity | yes | yes | yes |
| Contribute, propose, sign (if owner) | no | yes | yes |
| Cancel a proposal | no | own, while nobody else signed | any |
| Invite, change fund metadata, deploy, set roles | no | no | yes |

Admins set roles on the members page (`PATCH /users/:id` with `account_id` and `role`); a fund always keeps at least
one admin, checked under a row lock. Every form that changes a fund names it with `account_id`: the fund last viewed is
only a preference and is never acted on, and a prefetch does not change it.

App roles never grant on-chain power. Only Safe owners can sign. An admin removing a member does
not remove their Safe ownership; the UI prompts for a `remove_owner` proposal and shows the gap. The check reads the
live owners from the chain and compares them with every wallet that person ever verified, revoked ones included; when
the chain cannot be read the message says the check could not be done.

## Identity

The address on an account is unproven until confirmed (docs/SECURITY_REVIEW.md, H2). Registering sends a mail with a
24-hour link. The link page confirms only with this account's session or password, because a stranger could register
someone else's address and have the real owner confirm it with one click. Mail scanners only GET, which confirms
nothing. A password reset also confirms (the reset mail went to the address) and logs out every other session, so a
squatter loses the account to the address's owner. A link invitation's mailed proof confirms the account only when
the click comes back to the browser that asked for that mail; an admin naming an address proves nothing about who
registers it. Resending is limited to 3 per 10 minutes per account. Unconfirmed accounts with nothing attached are
removed after 7 days.

Until confirmed, an account can log in and look around, but cannot join a fund through an invitation addressed to its
email, link a wallet (challenge, link and handoff are refused with `email_not_confirmed`), be offered or accepted as an
owner (`owner_email_unconfirmed`), or send invitations.

Sessions end after 7 days without use and always after 30 days; the cookie expires with them. `/sessies` lists a
person's own sessions and ends one or all others. Login is limited per IP (10 per 3 minutes) and per address (20 per
10 minutes); reset mail per address (3 per 10 minutes); invitations per person (10 per 10 minutes) and per fund (30
per day). Wallet link and unlink send a mail to the account. The link message names the account's email, and the
browser refuses a message whose domain line is not the page's own host.

Wallet changes change nothing on-chain; the UI shows when an owner address no longer maps to an
active verified wallet, and offers `swap_owner`.

## Threat model

| Compromise | Result | Defence |
|---|---|---|
| Database / API tampering | Altered proposal shown | Client rebuilds and recomputes; refuses mismatch |
| Database tampering of `safe_address` | Contributions to another contract | Contribute page reads the Safe from the chain first: canonical singleton, no modules, no guard, canonical fallback handler, and the address recomputed from the deployment data. Shows the owners and threshold read from the chain. Not covered: a consistent tamper of address *and* deployment data naming different owners; the person has to recognise the owners shown |
| Stolen session | Can propose, cannot sign | Wallet signature needed; owners see every proposal |
| Malicious RPC | False balances or owners | Advisory only; contract enforces at execution |
| Tampered JS delivery (Bybit pattern) | Could make a wallet sign something else | **Not fully defended, and cannot be by a website.** CSP; subresource integrity on every importmap module and the stylesheet (stops a file altered between server and browser, not an altered server); the viem SHA-256 published on the transparency page; each signing page explains how to recompute the safeTxHash without us (`getTransactionHash` on the Safe, by explorer or `cast call`) and tells owners to read the wallet, use a hardware wallet and compare out of band. Those instructions come from the same server, which the page says |
| Single signer key lost | Lockout if threshold unreachable | Warnings at creation; threshold rules |
| Cross-chain replay of deployment | Anyone can recreate the Safe with original owners on another chain | Documented; never tell users to send to other chains |

## Browser/server contract

JSON unless stated; session cookie and CSRF token as usual. Amounts and nonces are decimal
strings; `chain_id`, `threshold` and `operation` are numbers. Hex is lowercase and `0x`-prefixed. Errors:
`{ "error": "<code>", "message": "<Dutch text>" }` with a 4xx status, or 503 `rpc_unavailable` when the chain
cannot be read. Not logged in is 401 JSON, not a redirect. Non-members get 404, the same as a missing fund.

```
POST   /wallet_challenges            { address, purpose }           -> { nonce, message }
POST   /wallets                      { address, nonce, signature }  -> { id, address }
DELETE /wallets/:id
GET    /wallets                                                      -> { wallets[] }
POST   /wallet_handoffs                                              -> { url, expires_at }   single use
GET    /wallet/handoff/:token                                        -> { name, expires_at, scope }   does not spend it; a browser (Accept: text/html) gets the confirmation page
POST   /wallet/handoff/:token                                        -> { name, scope, grant_expires_at }   spends it; a form post redirects to the linking page, shown only to the browser holding the grant

POST   /accounts/:account_id/safe    { chain_id, token_address, owners[], threshold,
                                       acknowledge_risk }           -> deployment
PATCH  /accounts/:account_id/safe    { deploy_tx_hash? }             -> deployment   omit the hash after "Create2 call failed"
GET    /accounts/:account_id/safe                                    -> deployment
GET    /accounts/:account_id/balance                                 -> { source, amount, as_of, native_amount }

GET    /accounts/:account_id/proposals?page=                                   -> { proposals[], page, next_page }   25 per page
POST   /accounts/:account_id/proposals                { kind, title, params, acknowledge_risk? }  -> proposal
GET    /accounts/:account_id/proposals/:id                                     -> proposal
DELETE /accounts/:account_id/proposals/:id                                     -> proposal   cancel, off-chain only
POST   /accounts/:account_id/proposals/:id/signatures { signature }            -> proposal
POST   /accounts/:account_id/proposals/:id/execution  { tx_hash }              -> proposal

POST   /accounts/:account_id/sync_requests            { tx_hash? }   hint only, credits nothing
GET    /accounts/:account_id/chain_events(.csv)
```

`deployment`: `{ status, chain_id, safe_address, owners[], threshold, salt_nonce, initializer,
factory, singleton, fallback_handler, deploy_tx_hash }`, plus `chain_name`, `testnet`, `token`,
`verification_error`, `verified_at`; before setup, nulls plus `available_chains`; when active, GET adds `live`
(owners with who they map to now). `safe_address` is a prediction until `status` is `active`: never show it as a
deposit address before then. The client recomputes `initializer` and the CREATE2 address from
`owners`/`threshold`/`salt_nonce` and refuses a mismatch.

`proposal`: `{ id, kind, title, params, state, chain_id, safe_address, to, value, data, operation,
safe_tx_gas, base_gas, gas_price, gas_token, refund_receiver, nonce, safe_tx_hash,
token: { address, symbol, decimals }, signatures: [{ signer, signature, user_id, name }], execution_tx_hash,
executed_at, proposer: { id, name }, created_at, live }`.

`live` is computed on every response and never stored: `{ available, executable, reason, owners, threshold,
current_nonce, valid_signers, valid_signature_count, missing_signatures, stale_signers, siblings, warnings, fund_balance }`,
or `{ available: false, error, message }` during an outage. `reason`: `not_open`, `tampered`, `nonce_passed`,
`waiting_for_earlier_nonce`, `calldata_stale`, `not_enough_signatures`, `balance_unknown`, `insufficient_balance`, or
null when executable. `warnings`: `sibling_at_same_nonce`, `lowers_threshold`, `insufficient_balance`, `nonce_gap`.
`state` adds `cancelled`. The execution
endpoint adds `execution_check`: `pending` (202), `reverted`, `unrelated`, `executed` or `failed`.

`params` per kind: `transfer_token { recipient, amount }`, `transfer_native { recipient, amount }`,
`add_owner { owner, threshold }`, `remove_owner { owner, threshold }`, `swap_owner { old_owner,
new_owner }`, `change_threshold { threshold }`, `rejection { nonce }`. `amount` is in base units.
`prev_owner` is never client-supplied to the server: each side derives it from a live `getOwners`.

Nonce on creation: see Nonce and queue rules. `rejection` takes the targeted nonce.

Pages pass data to Stimulus through `data-*-value` attributes; no inline scripts.

HTML pages have their own URLs, so one URL never answers in two formats (the handoff above is the exception):
`/dashboard`, `/wallet`, `/users` and under `/accounts/:account_id/`: `uitnodigen`, `safe_instellen`, `inleggen`, `activiteit`,
`transparantie`, `voorstellen` (`new`, `:id`, `reject`), `ramp`. Live reads are lazy turbo frames (`live/*`, `voorstellen/list`,
`voorstellen/:id/live`), rendered by the server from a fresh read, so a slow RPC never blocks a page and an outage reads as an
outage. Proposal forms post to the server in decimal strings; `Chain::Amount` converts them without floats.
`DELETE /users/:id` removes a membership (admin) and sends the admin to a `remove_owner` proposal if that member is an owner.

A handoff lasts 5 minutes unspent. Spending it sets a separate 15-minute cookie honoured only by
`POST /wallet_challenges` and `POST /wallets`; logging out or an expired session ends it. The confirmation page shows
`name` and the account's email and carries a CSRF token. Signing on a phone means logging in inside the wallet's
browser: the page after linking says so and links to the login. The grant used to cover reading and signing proposals
too; no page used that, so it was removed (stage F) and a leaked link now opens less.

`FUNDTOGETHER_CHAINS` lists enabled chain keys (default `sepolia`); `FUNDTOGETHER_RPC_URLS_<KEY>` puts operator
endpoints first, for the server only: pages get `chain.browser_config` / `public_rpc_urls` and the CSP gets
`public_rpc_origins`, both from `config/chains.yml`, so an endpoint with a key never reaches a browser; `FUNDTOGETHER_ORIGIN` sets the origin wallet messages and handoff links are bound to (production
default `https://$APP_HOST`).

## Production environment

| Variable | Required | What it does |
|---|---|---|
| `APP_HOST` | yes; boot fails without it | The public host name. `config.hosts` allows it and `www.` of it; mail links, share links and QR codes use `https://$APP_HOST` (through `FUNDTOGETHER_ORIGIN`), never the request's `Host` or `X-Forwarded-Host` |
| `ALLOWED_HOSTS` | no | Extra host names, comma separated |
| `FUNDTOGETHER_ORIGIN` | no | Overrides the origin for wallet messages and links. Default `https://$APP_HOST` |
| `TRUSTED_PROXIES` | when a proxy in front is not on loopback | Addresses or ranges allowed to set `X-Forwarded-For`. Default: loopback only. Rate limits by IP depend on it |
| `SECRET_KEY_BASE` / `RAILS_MASTER_KEY`, `RESEND_API_KEY`, database variables | yes | As before |

`/up` is exempt from the host check and from the HTTPS redirect, so a load balancer can call it by address. The
proxy must redirect plain HTTP to HTTPS (the app sets HSTS and Secure cookies but answers what reaches it) and should
drop a client's `X-Forwarded-Host`; with the host list it is refused anyway.

## Code layout and ownership

- `config/chains.yml`: registry of chains, RPCs, contracts, tokens. `Chain::Registry` is its only reader.
- `app/services/chain/`: `registry`, `rpc`, `abi`, `eip712`, `signature`, `safe_reader`, `safe_policy`,
  `proposal_builder`, `log_sync`, `deployment_verifier`, plus `hex`, `address`, `create2`, `refusal`,
  `threshold_rules`, `owner_eligibility`, `safe_configurator`, `wallet_linker`, `proposal_creator`,
  `signature_recorder`, `proposal_status`, `proposal_reconciler`, `execution_check`, `balance`, `csv_export`, `amount`.
- `app/javascript/wallet/`: EIP-6963 discovery, provider state machine, error mapping.
- `app/javascript/safe/`: deploy, EIP-712 hash, calldata, policy (viem, mirrors Ruby).
- `vendor/javascript/viem.js`: single committed build with recorded version and SHA-256, in
  `docs/VENDORED_JS.md`. Build inputs in `vendor/viem-build/`, no `package.json`.
- `app/javascript/controllers/`: thin Stimulus controllers. No business logic. Their contract for
  screens is `docs/FRONTEND_CONTRACT.md`.
- `test/fixtures/safe_vectors.json`: vectors asserted by both Ruby and JS, seeded from real
  Gnosis transactions verified by the research agent.

## Testing layers

1. Ruby unit tests with shared vectors and stubbed RPC. Runs in CI, no network.
2. JS tests with the same vectors.
3. Integration tests for authorization and failure cases.
4. Live Sepolia end-to-end: real browser with a test-only injected EIP-1193 provider that signs with
   throwaway keys. Keys come from a path outside the repo. Excluded from CI. The provider ships in
   `test/` only, never in the app bundle.
5. Evidence: real tx hashes in `docs/TESTNET_EVIDENCE.md`. No hash, no claim.

Requires humans, and must be reported as untested until done: real wallet extensions, phones,
hardware wallets, the Safe{Wallet} exit drill, a real-money ramp round trip, legal review.

# Security review, stage E

Independent adversarial review of the whole application, 2026-11-09. Report only: no application file was changed.

**Verdict.** I found no path by which a server-side attacker, a member or an outsider moves money without the owners' signatures, and no authorization bypass or XSS. The on-chain core held up. What did not hold up is everything around it: who a person is (identity), what links our mail contains, whether a single member can jam a fund, and a few places where the screen says something the chain does not. Not ready for mainnet until H1 to H4 are fixed.

## Status after stage F (hardening), 2026-11-09

Every reproduction above was rerun against the changed code (`scratchpad/security/*` plus a rerun file with today's
form parameters). Numbers are from this laptop in test mode.

| # | Status | What changed | Rerun of the reproduction |
|---|---|---|---|
| H1 | **Fixed** | Non-owners always propose at the live nonce; only proposals by owners or with a signature hold a nonce; owner changes always take the live nonce; caps 5 per member, 10 per owner, 30 per fund (owner changes and rejections by owners or admins exempt); cancel by proposer or admin; a departing member's proposals are cancelled; gap warning with "make again at the free nonce". Design in ARCHITECTURE, *Nonce and queue rules*. The "one open owner change" rule is gone, because it was itself the block | Junk: 5 at nonce 5, 6th `429`; junk owner change `429`; admin's payout nonce 5 (was 12), `remove_owner` 201 at nonce 5 (was `409`); after removing the griefer 0 open (was 6). Live: journey H |
| H2 | **Fixed** | Email confirmation: 24 h token, needs the account's session or password, mail scanners' GET does nothing; resend limited; password reset confirms and logs out a squatter; link-invitation proof counts only in the browser that asked for it. Unconfirmed: no addressed join, no wallet, not an owner, no invitations | K: register leads to `/email_bevestigen`, not a member, link `403 email_not_confirmed`, key not offered, `add_owner` `422 owner_email_unconfirmed`; the real owner clicking a squatter's mail without the password: 422 |
| H3 | **Fixed** | Mail and share links use `PublicUrl` (configured origin); `config.hosts` from `APP_HOST` (+`ALLOWED_HOSTS`), `/up` excluded; `APP_HOST` required at boot | Test mode: mail and share page `https://fundtogether.test/…` under `Host: evil.test`. Production mode: `Host: evil.test` 403, `X-Forwarded-Host: evil2.test` 403, `/up` 200 by IP, mails `https://fundtogether.example` |
| H4 | **Fixed** | Recovery once per signature row (keyed MAC), live owner check every read; closed proposals not computed; one balance read per list; lists page closed proposals (25), JSON index paginated; 60 frames/min, 30 index/min per user | Probe 8 data (100 × 3): before 23.4 s list, 23.2 s attention, 23.0 s JSON, every request. After: 25 s once for rows stored before this change (signatures made through the app are stored verified), then 0.07 s, 0.03 s, 0.02 s. 70 frames in a minute: 60 × 200, 10 × 429. Probe 8 itself can no longer create 100 open proposals (cap) |
| H5 | **Mitigated, cannot be closed** | SRI (sha384) on every importmap module and the stylesheet; viem SHA-256 published on the transparency page and tested equal to the file; signing page panel "Zo controleer je dit zonder FundTogether" with the hash, `getTransactionHash` via explorer, a prefilled `cast call`, wallet and hardware-wallet guidance; residual risk stated on the transparency page and in ARCHITECTURE. A compromised server can change all of it, which the page says | n/a |
| M1 | **Mitigated** | Contribute checks code, canonical singleton, no guard, canonical fallback, no modules, and recomputes the CREATE2 address from the deployment data before any prompt; shows destination, owners and threshold read from the chain. Not checkable in a browser: that a consistent tamper of address and deployment names the right people | JS tests refuse look-alike singleton, guard, module, fallback, address mismatch, with no wallet prompt; live journey H |
| M2 | **Fixed** | 10 per person per 10 min, 30 per fund per day, on create and send_email; unconfirmed admins cannot invite | J: 60 tries → 10 accepted, 10 mails (was 60) |
| M3 | **Fixed** | Claimed hash must exist and be this fund's `createProxyWithNonce` call; not found is ignored; verification backs off to 1 h and gives up after 30; 5 funds per hour per person | Probe 9: 0 funds flipped (was 10); 0 verification jobs |
| M4 | **Fixed** | Unfinalized rows re-checked in one batched request; unknown senders in full and checksummed; look-alike warning; unknown-sender dust collapsed behind a toggle, kept in data, totals and CSV, left off the dashboard | Probe 7: idle sync with 40 dust rows 5 RPC calls (was 44; 4 with none) |
| M5 | **Fixed** | Message names the account's email; browser refuses a domain line that is not `location.host`; mail on link and unlink; handoff page names the email | M2 rerun: message contains `Account: <email>`. The phished-signature scenario still links if the victim signs a message naming someone else's email: that is now visible, not impossible |
| M6 | **Fixed** | Bidi, zero-width and control characters stripped at input (names, titles, fund name and description) and neutralised at display for old rows; `<bdi>`; title labelled as proposer's text; duplicate-name warnings; full checksummed addresses on member, signer and recipient lines | F: stored title bidi kept false; RLO in HTML false; `bdi` present |
| M7 | **Fixed** | Removal compares live `getOwners` with every wallet the person ever verified; RPC failure says the check could not be done | N2, N3: both warn and redirect to `remove_owner` (were plain success) |
| M8 | **Fixed** | Path tokens filtered in `Started` lines and redirects, mail job arguments and mail bodies not logged; `signature`, `address`, `nonce` filtered | P: no handoff, invite or reset token, no signature or address in the log |
| M9 | **Fixed** | Every fund-changing form posts `account_id`; without it the action does nothing; prefetch does not switch funds; roles likewise | D: removal and invite act on A while B was viewed last; no fund named: refused |
| M10 | **Fixed** | Execution hint only applies execution events matched by `safeTxHash`, never the nonce; an execution event supersedes its siblings; a lower nonce reopens a superseded proposal only after a reorg seen by hash | 2a/2b: unrelated hint leaves it open, no "Vervallen"; 2e: lagging nonce does not reopen |
| M11 | **Fixed** | `insufficient_balance` / `balance_unknown` computed live; never ready; panel offers cancel and rejection; browser refuses `insufficient_fund_balance` before sending | 11a: `executable=false reason="insufficient_balance"` |
| M12 | **Fixed** | ETH balance read and shown when present; executed payouts show amount and recipient from the proposal, labelled; CSV filled | 11d: "Voorstel uitgevoerd −… ETH naar 0xE57b…"; 11e CSV has recipient, amount, `ETH` |
| M13 | **Fixed** | 7 days idle, 30 days absolute, cookie expires with it; `/sessies` lists and ends sessions; handoff grant ends with the session | Cookie no longer expires in 2046 |
| M14 | **Mitigated** | Per-address limits on login (20/10 min) and reset mail (3/10 min); `TRUSTED_PROXIES` from env, loopback by default | Rotating source addresses: limited by address. Whether the real proxy appends or overwrites `X-Forwarded-For` is untested (no proxy here) |

| # | Status | Reason or test |
|---|---|---|
| L1 | **Fixed** | Payout rows use the stored attribution and show the short address. `LowFindingsTest` *keeps the name it had* |
| L2 | **Fixed** | Attribution needs an active membership joined by the event time. `ChainLogSyncTest` *inactive member and someone who joined after* |
| L3 | **Fixed (labelled)** | Tile reads "Jouw inleg, vóór uitbetalingen". Net per member needs a payout-to-member model; not built |
| L4 | **Fixed** | `1.000` and every `d{1,3}(.ddd)+` refused in Ruby and JS with an explanation; the parsed amount is echoed under the field. `LowFindingsTest`, JS *L4*, live journey H |
| L5 | **Fixed** | Missing or non-string login fields, NUL anywhere (400), array or huge page and member parameters. `LowFindingsTest` |
| L6 | **Fixed** | Duplicate-key check includes revoked wallets; `swap_owner` stays available. `LowFindingsTest` *second key* |
| L7 | **Accepted, documented** | `assume_ssl` means the app cannot see plain HTTP; the proxy must redirect (ARCHITECTURE, Production environment). Production probe: plain HTTP still 200 |
| L8 | **Fixed** | Formula after a `;`, `,` or tab also prefixed; leading Unicode spaces too. `LowFindingsTest` *CSV* |
| L9 | **Fixed** | Only the used frameworks load: no Active Storage, Action Mailbox or Action Text routes. Production probe: direct uploads 404 |
| L10 | **Fixed** | Description at most 2,000 characters. `LowFindingsTest` |
| L11 | **Partly fixed** | Sync jobs discard on conflict (`LowFindingsTest`). Running workers outside Puma is a deployment choice; documented, not changed here |
| L12 | **Fixed** | Handoff confirmation names the account's email; the grant now only covers linking. `IdentityAndLoggingTest` |
| L13 | **Partly fixed** | CI has a Node job pinned to 20.10.0 running `test/javascript` (with the viem hash check); `bundler-audit check --update` in CI. The local advisory database was updated (1,353 advisories, 2026-11-09): no vulnerabilities. Actions and the Docker base image are still pinned by tag: pinning by digest needs the network and a policy for updates, left for the operator |

Other changes in this stage: admins set roles (admin, member, viewer) on the members page, a fund always keeps one
admin; the wallet handoff no longer opens proposal reading or signing (no page used it), and the page after linking
tells a phone user to log in inside the wallet browser to sign; the wallet pill shows a checksummed address from a
server-made map without loading viem.

## How this was tested

- **Integration probes** against the real controllers and services, with the repo's `FakeRpc` as the chain, on a throwaway database. Exploits below marked *ran* come from these.
- **Production mode** booted locally on port 3917 with a test secret and four separate databases, including one recurring job run on the queue database. Mail workers were off during the mail probes, so nothing reached Resend.
- **Parity fuzz**: 20,000 generated proposals through both `assertPolicy` (JS) and `Chain::SafePolicy` (Ruby), plus amount, signature and address cases.
- **Read-only** on Sepolia: one `eth_getStorageAt`. No transaction was sent and `keys.json` was not read. All review databases were dropped afterwards.
- Probes are in the scratchpad, `security/probe_authz_test.rb`, `probe_chain_test.rb`, `probe_chain2_test.rb`, `fuzz.mjs`, `fuzz.rb`, `prod_probe.py`.

**Not tested:** XSS was checked in rendered HTML and mail source, not by executing a payload in a browser. No real wallet, real reorg, Excel, or real proxy in front of the app (Thruster, kamal-proxy, or a load balancer). Tampered-response cases in the browser were read in code and rely on the earlier evidence run, not on a new one. The concurrent thread stall in H4 is extrapolated from single-request timings.

## Summary

| # | Severity | Finding | Status after stage F (2026-11-09) |
|---|---|---|---|
| H1 | High | Any member can park the nonce queue and block owner changes | Fixed: `ProposalQueueTest` (22 tests, e.g. *the griefing reproduction*), live journey H |
| H2 | High | No email confirmation: a forwarded invite registers as that person, then is offered as a signer | Fixed: `EmailConfirmationTest` (21 tests) |
| H3 | High | Invitation mail links follow `Host` and `X-Forwarded-Host` | Fixed: `MailLinkHostTest`; production boot checked |
| H4 | High | Proposal list costs up to 41 s per request, unthrottled, with 3 Puma threads | Fixed: `AvailabilityHardeningTest` (recovery, pagination, frame limits); 23 s per request to 0.07 s |
| H5 | High | Tampered JS delivery (Bybit pattern) | Mitigated, residual risk accepted and documented: `LowFindingsTest` (SRI, viem hash, signing panel) |
| M1 | Medium | Contribute sends to whatever `safe_address` the server rendered | Mitigated: `test/javascript/hardening.test.mjs` *M1*; live journey H |
| M2 | Medium | Unlimited invitation mail with attacker-chosen text | Fixed: `InvitationRateLimitTest` |
| M3 | Medium | Free "deploying" funds create recurring RPC work | Fixed: `AvailabilityHardeningTest` (*made-up deploy hash*, *backs off*, *fund creation is limited*) |
| M4 | Medium | Dust transfers: look-alike senders and RPC amplification | Fixed: `AvailabilityHardeningTest` (*dust rows no longer drive RPC volume*, *collapsed behind a toggle*, *look-alike*) |
| M5 | Medium | Wallet link message names no account; no mail on link or unlink | Fixed: `IdentityAndLoggingTest` (*link message names*, *linking and unlinking send mail*), JS *M5* |
| M6 | Medium | Bidi characters and duplicate names on signing pages | Fixed: `IdentityAndLoggingTest` (*bidi*, *same name*, *add-owner form*), JS *M6* |
| M7 | Medium | Removing an owner often gives no warning | Fixed: `ProposalHonestyTest` (*added after deployment*, *unlinked first*, *chain cannot be read*) |
| M8 | Medium | Reset, invitation and handoff tokens in logs | Fixed: `IdentityAndLoggingTest` *tokens stay out of every log line* |
| M9 | Medium | Actions apply to the fund last viewed, not the page's fund | Fixed: `AvailabilityHardeningTest` *the form for fund A acts on A* |
| M10 | Medium | Any member can show an executed proposal as superseded for a while | Fixed: `AvailabilityHardeningTest` (*unrelated mined transaction*, *lagging node*, *lower nonce alone*) |
| M11 | Medium | Over-balance proposal says ready and blocks its nonce | Fixed: `ProposalHonestyTest` *over-balance*, JS *M11*; live journey E |
| M12 | Medium | ETH appears in no balance; native payouts show no amount or recipient | Fixed: `ProposalHonestyTest` (*ETH next to the token*, *native payout shows amount and recipient*) |
| M13 | Medium | Sessions never expire | Fixed: `IdentityAndLoggingTest` (*idle limit and the absolute limit*, *sessions*) |
| M14 | Medium | Rate limits are per IP only, and depend on proxy trust | Mitigated: `IdentityAndLoggingTest` (*per address*, *trusted proxies*); real proxy untested |
| L1-L13 | Low | See below | See the status table below |

## High

### H1. Any member can park the nonce queue and block owner changes

- **Where:** `app/services/chain/proposal_creator.rb:77-89` (nonce is highest open + 1), `:70-75` (one open owner change), `config/routes.rb` (no cancel route).
- **Reproduction (ran, probe E):** a member who is not an owner created 5 junk transfers and a junk `change_threshold`. They got nonces 6 to 11. The admin's next real proposal got nonce 12 with the chain at 5, reason `waiting_for_earlier_nonce`. The admin's `remove_owner` got `409 owner_change_pending`. After removing the griefer, all 6 proposals stayed open. `DELETE` and `PATCH` on a proposal are 404.
- **Impact:** funds cannot be stolen this way, but the fund is jammed in the app. Every parked nonce must be consumed on-chain, with threshold signatures and gas, before later work can run. The limit of 20 per minute allows 28,800 nonces per day per account. It also lets a compromised member stop the group removing an owner, which is when speed matters most. Owners can still act through Safe{Wallet}, but the app keeps numbering above the parked range.
- **Fix:**
  1. Let a proposal take the current or lowest free nonce, not highest + 1, so a new proposal can compete at the live nonce.
  2. Add off-chain withdrawal for proposals: by the proposer or an admin, always when unsigned. A signed one must still be rejected on-chain or the UI must say that signatures remain valid.
  3. Cap open proposals per fund and per proposer.
  4. Close a removed member's unsigned proposals.
  5. Count `owner_change_pending` only for proposals that have signatures, or allow it to be overridden.

### H2. No email confirmation: a forwarded invite registers as that person

- **Where:** `app/controllers/registrations_controller.rb:18-32`, `app/models/invitation.rb:82-84`, `:86-99`.
- **Reproduction (ran, probe K):** with an addressed invite for `bas@example.com`, an anonymous client posted accept, then registered as `bas@example.com` with its own password and name "Bas Jansen". Result: active member. It then linked its own wallet. The admin's `add_owner` form offered that key as "Bas Jansen" and the proposal was created (201). Any address can also be pre-registered without a link (K6), so the real owner of that address finds it taken.
- **Impact:** the link is only a bearer token, and the address check proves nothing, because the registrant simply types the address. The attacker reads the fund and can propose. The serious case is signers: owners approve a key because the name is one they know. That approval is what gives on-chain power.
- **Fix:** confirm the address before an account exists or before it can join a fund. Require a fresh mailed token at accept. On `add_owner` and `swap_owner`, tell owners to confirm the address with the person out of band.

### H3. Invitation mail links follow the request host

- **Where:** `config/environments/production.rb:100` (`config.hosts` commented out), `app/controllers/invitations_controller.rb:38,160,186` (`open_invitation_url`).
- **Reproduction (ran in production mode):** `POST /invitations` with `Host: evil.test` queued a mail with `https://evil.test/invitations/<token>/open`. With `X-Forwarded-Host: evil2.test` it queued `https://evil2.test/...`. The redirect also went to `https://evil.test/invitations/success`. Any `Host` got a 200, and `www.evil.test` was not redirected in this run.
- **Impact:** anyone can register, create a fund and have FundTogether's own domain send a victim a link to a phishing site, which can then ask for wallet signatures. The real token also leaks to that host. Whether it works live depends on what the proxy forwards, which I could not test. `WalletChallenge.origin` and the mailer defaults do use configuration, and held up.
- **Fix:** set `config.hosts` from `APP_HOST`. Build invitation links from the configured origin, never from the request. Have the proxy drop `X-Forwarded-Host`.

### H4. Proposal list cost

- **Where:** `app/services/chain/proposal_status.rb:21-47`, `app/models/proposal_view.rb:6-10`, `app/services/chain/signature.rb:73-89`, `app/controllers/live_controller.rb`, `config/puma.rb` (3 threads).
- **Reproduction (ran, probe 8):** one recovery takes 79 ms in pure Ruby. With 100 proposals of 3 signatures each: list 41.3 s, attention frame 23.1 s, JSON index 23.4 s, on this laptop in test mode. No rate limit applies. Closed proposals are recovered too.
- **Impact:** any fund reaches this through normal use. An attacker needs only a cheap Safe of their own and proposals signed at no gas cost, though with one signature each the cost is roughly a third. Three looping requests would hold all three Puma threads. That last step is extrapolated, not measured.
- **Fix:** skip recovery for closed proposals. Cache recovery per signature row, since the input is immutable. Paginate. Rate limit live frames.

### H5. Tampered JS delivery (residual)

- **Where:** threat model in `docs/ARCHITECTURE.md`. Theoretical, not exploited.
- **Impact:** code served from our origin decides what the wallet is asked to sign and what the page shows, including the hash to compare. CSP, digests and vendored code do not stop tampered same-origin delivery. Rated high because this is how real multisig losses have happened.
- **Fix:** this cannot be fully closed. Before mainnet, require a hardware wallet recommendation and document an independent hash check that is hosted elsewhere. Make the comparison step part of the flow, not just a sentence. Hold owners to reading the typed data in the wallet.

## Medium

### M1. Contribute trusts the rendered Safe address

`app/javascript/safe/flows.js:279-290` checks only `hasCode(safe)`; `safe_address` comes from `data-contribute-safe-address-value`. The proposal flow does verify the singleton (`verify.js:94`), this one does not. So the "database tampering" row of the threat model does not cover contributions: a changed `safe_address` pointing at any contract receives members' tokens. The page's QR and copy field have the same source. *Code read only.* **Fix:** in the browser, check singleton, modules and guard, and recompute the CREATE2 address from owners and salt before sending. Show the owners.

### M2. Unlimited invitation mail

`app/controllers/invitations_controller.rb:13-22` limits `send_invitation_email` but not `create`. *Ran, probe J:* 60 of 60 invites accepted under a working limiter, 60 mail jobs queued. Subject and body carry a fund name (100 characters) and inviter name chosen by the attacker. Impact: spam and phishing relay from our domain, sender reputation, Resend cost. **Fix:** limit per user and per fund, and count distinct recipients per day.

### M3. Free "deploying" funds

`app/controllers/safes_controller.rb:30-36`, `accounts_controller.rb:9` (no limit), `app/jobs/chain_sync_scheduler_job.rb:10-12`. *Ran, probe 9:* one user and one wallet flipped 10 funds to `deploying` with made-up tx hashes, no gas. The scheduler then queued 10 verification jobs per minute; that minute used 34 RPC calls with 2 ordinary syncs included. The 20 per minute route limit allows about 14,400 such funds per day, each lasting 24 hours. **Fix:** check the hash exists and targets the factory before leaving draft. Limit funds per user. Use backoff in the scheduler.

### M4. Dust transfers

`app/services/chain/log_sync.rb:191-207` filters zero only; `:70-81` re-reads each unfinalized block; `app/helpers/fund_helper.rb:55-58` and `_event_row.html.erb:40` show 4+4 hex characters. *Ran, probes 3 and 7:* 1 wei and 1 token unit from a look-alike were recorded and shown as "Onbekende afzender" with `+0,000001 EURC`, shortened to the same characters as the member's address apart from letter case. 40 such rows in distinct blocks raised an idle sync from 4 to 44 RPC calls. No account is needed. **Fix:** show unknown senders in full. Collapse rows below a threshold without dropping them from the data. Fetch block hashes in one batch or per range. Warn when a recipient resembles an address already seen.

### M5. Wallet link message names no account

`app/models/wallet_challenge.rb:58-72`, `app/services/chain/wallet_linker.rb:49-54`. *Ran, probe M1-M3:* an account requested a challenge for an address it does not control; a signature from that key linked the wallet to the attacker. The message says "je FundTogether-account". This needs phishing; a wallet may warn on the domain. Impact: the victim's later contributions are attributed to the attacker, and the victim gets `wallet_taken`. No mail goes out on link or unlink (known item, confirmed by reading: the wallet controllers send none). A stolen session can therefore link a wallet unnoticed. **Fix:** put the account's email or a short fingerprint in the message, have `link.js` check the domain equals `location.host`, and mail on link and unlink.

### M6. Bidi characters and duplicate names

`app/services/chain/proposal_creator.rb:13`, `app/views/proposal_pages/show.html.erb:9-10`, `_person.html.erb:5`, `app/helpers/fund_helper.rb:145-147`. *Ran, probe F:* a title with U+202E was stored and rendered as is; no `<bdi>` or `dir="auto"` anywhere. A second member named exactly like the admin was shown with that name above a different address. The title is free text in the largest heading of the page, unlabelled. It can say a different amount or recipient. Lists show only the name, without the address. The browser-computed summary does stay correct and in full. **Fix:** strip bidi and zero-width controls from titles and names on input; render with `<bdi>`. Label the title as the proposer's text. Flag duplicate names. Show the address next to any name on money and signer lines.

### M7. Removing an owner often gives no warning

`app/controllers/users_controller.rb:22-26` compares against `safe_owners` (the deployment intent, never updated) and the member's active wallets. *Ran, probe N:* removing an owner added after deployment, and removing an owner who unlinked first, both returned plain success with no warning. `docs/ARCHITECTURE.md` says the UI must prompt. A malicious owner can unlink first. The attention frame still shows the gap (read in code). **Fix:** compare against live `getOwners` and all of the user's wallets, including revoked ones. On an RPC failure, say the check could not be done.

### M8. Tokens in logs

`config/initializers/filter_parameter_logging.rb:6-8` filters parameters, not paths. *Ran, probe P:* the `Started` line holds handoff tokens, invitation tokens and password reset tokens in full. Reset links are the worst: they allow account takeover for their lifetime, for anyone with log access. `signature` and `address` are also logged unfiltered in `Parameters`. **Fix:** filter path tokens in a log formatter, or have the link land on a page that posts the token. Add `signature`, `address` and `nonce` to the filter.

### M9. Actions apply to the fund last viewed

`app/controllers/fund_pages_controller.rb:23-27`, `users_controller.rb:16`, `invitations_controller.rb:32`, `settings_controller.rb:21`. *Ran, probe D:* an admin of two funds opened the members page of A, viewed B in another tab, then submitted A's removal form: the member was removed from B and stayed in A. An invite went to B likewise. A GET carrying prefetch headers also switched the fund; whether Turbo really triggers this was not tested in a browser. **Fix:** put the fund id in these routes and forms. Do not write state on GET, or at least skip prefetch requests.

### M10. Executed proposal shown as superseded

`app/services/chain/execution_check.rb:20-21`, `proposal_reconciler.rb:34-40`. *Ran, probes 2 and 11f:* with the chain nonce moved and the event not yet scanned, a member's hint for any unrelated mined tx set a really executed proposal to `superseded`. The next sync corrected it, and a sync outage would prolong it. Separately, a lagging nonce reopens a superseded proposal as `open` (2e). **Fix:** in `ExecutionCheck` pass `chain_nonce: nil` unless the scan has caught up, and never let the nonce go backwards.

### M11. Over-balance proposal says ready (known item)

`app/services/chain/proposal_status.rb:25-33`. *Ran, probe 11a-b:* balance 0, `executable: true`, reason null; the next proposal queues behind it. Impact is compounded by H1. **Fix:** add a live balance check as a separate warning, not a refusal, and point the message to rejection.

### M12. ETH appears in no balance; native payouts have no amount (known item)

`app/services/chain/balance.rb:7-10`, `app/views/activity_pages/_event_row.html.erb`. *Ran, probe 11c-e:* with ETH in the Safe the frame says `0,00 EURC`. A native payout row reads "Voorstel uitgevoerd", date and status only, and its CSV row has empty from, to and amount, so ETH can leave with no visible figure. **Fix:** read and show the native balance. Join the execution event to its proposal and show the decoded amount and recipient, labelled as from the proposal.

### M13. Sessions never expire (known item)

`app/controllers/concerns/authentication.rb:50`. *Ran in production mode:* the cookie expires in 2046; the database row has no expiry. There is no session list and no re-authentication for wallet linking. **Fix:** idle and absolute expiry, a "log out everywhere" action, a fresh password before linking a wallet.

### M14. Rate limits per IP only

`sessions_controller.rb:5`, `registrations_controller.rb:5`. *Ran in production mode:* after the limit was reached, 13 tries with rotating `X-Forwarded-For` were not limited, and the correct password was accepted. This was from a loopback peer, which Rails trusts as a proxy. Whether it applies live depends on the proxy overwriting or appending that header. Independently of that, no per-account limit exists, so distributed guessing is unbounded. **Fix:** add a limit per email address. Verify the header behaviour of the real proxy.

## Low

| # | Finding | Where | Evidence and fix |
|---|---|---|---|
| L1 | Payout rows relabel history after a wallet moves | `_event_row.html.erb:17`, `fund_helper.rb:122-128` | *Ran, probe 4:* stored Xz, page shows "naar Yz". Use `event.user` |
| L2 | Attribution ignores `active` and membership time | `log_sync.rb:234-240` | *Ran, 4d:* inactive member attributed; someone who joined after sending too. Scope to `active` and `joined_at` |
| L3 | "Jouw inleg" is gross | `pages_controller.rb:27-30` | *Ran, probe 5:* shows 300 EURC when net 100. Needs approved payouts. Label as gross or show net |
| L4 | Dutch-looking amounts misread | `amount.rb:10`, `amounts.js:8` | *Ran, L22:* `1.000` is 1 token, while pages format thousands with a dot. The review shows the result. Refuse a dot followed by exactly 3 digits |
| L5 | Unhandled input gives 500, no stack leak | `sessions_controller.rb:11`, `chain_events_controller.rb:26`, `activity_pages_controller.rb:10`, NUL in title or names | *Ran:* login without password, page overflow, NUL byte. Clamp and validate |
| L6 | Second key for one person | `owner_eligibility.rb:25-29` | *Ran, N1:* unlink, link new, `add_owner` gives 201. Compare with revoked wallets too |
| L7 | HTTP not redirected | `production.rb:28,31` | *Ran:* with `assume_ssl`, plain HTTP gets 200. HSTS and Secure cookies are present. The proxy must redirect; document it |
| L8 | CSV separator confusion | `csv_export.rb:5` | *Output seen, Excel not opened:* `x;=1+1` is not prefixed, and Dutch Excel splits on `;`. Prefix any cell containing a separator followed by a formula character, or use `;` and quote deliberately |
| L9 | Unused engines exposed | `config/application.rb:3` | *Ran:* `/rails/active_storage/direct_uploads` raises on missing tables; mailbox routes exist. Load only the needed frameworks |
| L10 | Long fund description accepted | `account.rb:19` | *Ran, L33:* 2 MB stored. Add a length limit |
| L11 | Job pile-up and worker coupling | `chain_sync_job.rb:4`, `Dockerfile` | *Code read:* blocked syncs can accumulate; use `on_conflict: :discard`. *Seen:* "Solid Queue has gone away, stopping Puma" after a macOS fork crash, so with `SOLID_QUEUE_IN_PUMA` a supervisor failure stops the web server. Run workers separately |
| L12 | Handoff fixation | `wallet_handoff_redemptions/show.html.erb` | *Theoretical:* attacker's QR, victim's fresh wallet links to the attacker's account. The name shown is attacker-chosen; the warning helps. Same fix as M5 |
| L13 | Supply chain gaps | `.github/workflows/ci.yml`, `Dockerfile` | See below |

**L13 details.** `bundler-audit` says no vulnerabilities, but the local advisory database dates from 2025-12-21, 11 months old, and I did not update it, so this says little. Rails 8.1.1, Puma 7.1.0 and Rack 3.2.4 should be rechecked. CI has no Node job, so the JS tests and the vendored viem hash check in `isolation.test.mjs` never run there. Actions and the Docker base image are pinned by tag, not by digest. `bin/importmap audit` does not cover vendored files.

**Theoretical, no action now.** EIP-7702: a delegated owner still signs with its key, so Safe signature checks hold, but delegate code can act for that EOA, and `getCode` is only read at link time. A token emitting a non-standard `Transfer` would stop `LogSync` at `fetch_logs`, which is not possible with the listed tokens. A lying RPC can activate a look-alike on the server side; this is documented as advisory, and M1 is what makes it reach contributions.

**Docs that disagree with the code.** `ARCHITECTURE.md`, Authorization (M7) and threat model (M1). `docs/SECURITY_AUDIT.md` is from December 2025 and describes an older app.

## What held up

**Authorization.** Every `/accounts/:account_id` route was hit as outsider, removed and inactive member: all 404. Anonymous: 401 or login redirect. Viewer: reads only, 403 or redirect on actions. Fund B's proposals through A's path: 404 for read, sign and execute. Another user's wallet, fund, invitation and member: refused. A forged `current_account` grants nothing. A query parameter cannot override the path's fund. Mass assignment on accounts, registration and invitations had no effect.

**Money display.** Spoofed `Transfer` from a fake token, `ExecutionSuccess` from another Safe or contract, a reverted receipt and unknown hashes credited nothing and changed no state. Zero-value and self transfers, and `SafeReceived` from the Safe or of zero, were not recorded. A transfer between two funds' Safes appears once in each. Reorg removed rows and reopened the proposal; a re-mined tx ended with one correct row. Relinking did not change stored attribution.

**Signing.** Raw `to`, `data`, `value`, `operation`, `nonce` in the request are ignored. Extra params are refused. Recipient as Safe or token, owner as sentinel, zero, Safe or token, and unknown kinds were all refused. Parity fuzz of 20,000 cases, including approve-style selectors, module, guard and fallback selectors, dirty padding and trailing bytes: **no case where one side allowed and the other refused**. Only 98 cases were allowed by both, and differences were limited to which refusal code came first on malformed input. Ruby accepts all-caps addresses without a checksum where JS refuses; harmless, since the address is then normalized. `personal_sign` cannot be turned into a Safe `eth_sign` signature because the client requires the address and nonce in the message, which does not fit in 32 bytes (read in code).

**Signatures.** Replay across proposals and chains, high-s, v 31/32 and an unlinked wallet: refused. v 0/1 normalized to 27/28. Same signature in upper case: idempotent. 120 edge signatures (r and s at 0, 1, n-1, n, n+1, n/2, maximum; bad v) gave the same normalization and recovered signer in Ruby and viem. Challenge replay, expiry, another user's nonce and high-s or v+4 on `personal_sign`: refused. Contract code refused, valid 7702 designator accepted, over-long one refused.

**Deployment.** Initializer has zero `to` and empty `data`. Module, guard, fallback handler, singleton, threshold and owner order mismatches each stayed in draft with the right error. A clean Safe became active. An active fund cannot be reconfigured or deleted. No path from input to an RPC URL (read in code); RPC errors log hosts only.

**Web.** No HTML injection in fund names, user names, titles, flash, frames or mail HTML. Subject with CRLF is encoded, no `Bcc` header results. CSRF enforced on every state-changing route, JSON included, except routes that have no action. Formula-prefixed CSV names are neutralized. Ramp links resolve only within the fund's catalog (read in code and existing tests). Login resets the session (read in code). Handoff grant is limited as documented, single use, dies with membership and session, and sends `no-store`.

**Numbers.** `2^256 - 1` stores and renders; `2^256`, 100 digits, full-width digits, trailing newline, huge or fractional thresholds refused.

**Production mode.** HSTS, Secure, HttpOnly and SameSite=Lax cookies. CSP as documented, with a per-request nonce, no external hosts in page or importmap, no inline script without a nonce. Error pages leak nothing. The recurring job ran on the separate queue database, and the primary has no queue tables. `/rails/info` 404, conductor 403, `/cable` 404.

**Supply chain.** `vendor/javascript/viem.js` is `10e91b80…cd781`, as documented. Rebuilt offline from the committed lockfile and the same esbuild flags, it gives the identical hash. `eval`, `new Function`, `WebAssembly`, `localStorage`, `fetch(`: zero matches. Brakeman: 0 warnings. `master.key` is ignored and in `.dockerignore`. Singleton on the main Safe read from Sepolia matches the registry.

## Suggested order

1. H2, H3, M2: identity and mail. These are small changes with the largest effect.
2. H1, then M11 and M7: keep a fund operable and honest about owners.
3. H4, M3, M4: availability, before any public signup.
4. M1, M5, M6: signing and sending screens.
5. M8, M9, M10, M12, M13, M14, then the low items. Recheck dependencies with an updated advisory database and add a Node job to CI.

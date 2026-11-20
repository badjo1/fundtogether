# 04. Wallet connection and onboarding research

Date: 2026-11-08. Repo read only, nothing changed. No package was installed or executed; sizes come from registry JSON, jspm's generator API and esm.sh responses.

Evidence labels:

- **[P]** probed or measured directly in this session (live RPC, HTTP, registry, source file)
- **[D]** read on a first-party doc or license
- **[S]** secondary source or search snippet only
- **[U]** unverified: from memory or inference, must be confirmed

## 1. Recommendation

1. **No wallet framework.** Build a small dependency-free layer: EIP-6963 + EIP-1193 + a singleton state machine + a thin Stimulus controller. The link flow needs no library in the browser, because the server composes the SIWE message.
2. **Primary mobile route is a QR or deep-link handoff into the wallet's own browser**, which uses the injected provider and does not touch the relay. It needs a scoped, single-use handoff token, because wallet browsers do not share the user's cookies.
3. **WalletConnect is an optional, lazy-loaded second route, off when no project ID is set.** Use `@walletconnect/ethereum-provider` headless with our own QR. It is not on the critical path because the relay is proprietary and the free tier is "cut off at limit" (section 3).
4. **viem** only as a tree-shaken vendored bundle, loaded on Safe signing pages, shared with protocol-kit.
5. **Vendor with a one-off esbuild step on a dev machine or in CI; commit the output.** No Node in production. `bin/importmap pin` does not work for these packages (section 2.3).
6. **Link wallets only. No SIWE login at launch.** New `wallets` table (one user, many wallets; one active address, one user). Safe ownership lives on the membership, not on the user.
7. **Account abstraction: not at launch, but keep the seam.** Launch with a guided EOA path. Pilot a passkey Safe owner in phase 2: the contracts are audited, deployed on Gnosis and Base, and the precompile is live. The main objection is ownership, not maturity (section 5).
8. **Remove the Tailwind CDN before any wallet code ships.** It is a third-party script with full DOM control on a page that will show signing requests, and it blocks a meaningful CSP.

**Blocking input from the team lead:** the target chain. Gnosis rules out Base Account and the Base app (section 5.3). This report assumes Gnosis (100) as the leading candidate and keeps the layer chain-agnostic.

## 2. Library comparison

### 2.1 Measured import graphs

Versions as of today [P]. "jspm" = static graph via `api.jspm.io/generate`, gzip summed per file with no tree shaking, so an upper bound. "esm.sh" = single-file `?bundle` of the whole entry point.

| Package | esm.sh raw / gz | jspm files / packages / sum gz | Notes |
|---|---|---|---|
| EIP-6963 + EIP-1193 by hand | 0 | 0 | Roughly 150 lines of our own code (estimate) |
| `mipd@0.0.7` | n/a | 1 / 1 / about 1 KB | Last published 2024; not needed |
| `viem@2.57.17` (whole root) | 388 KB / 119 KB | 116 / 8 / 179 KB | Tree shaking will reduce this; real figure known only at first build |
| `viem/siwe` | 205 KB / 64 KB | n/a | Not needed, server composes the message |
| `@wagmi/core@3.6.9` | 55 KB / 16 KB + viem | 133 / 12 / 203 KB | Connectors extra; WC still needed for mobile |
| `@walletconnect/ethereum-provider@2.26.0` | 1657 KB / 459 KB | 211 / 46 / 478 KB | Static graph excludes the modal, see below |
| `...ethereum-provider` `dist/index.umd.js` | 1423 KB / 396 KB | n/a | Prebuilt, classic script, contains AppKit strings |
| `@reown/appkit@1.8.24` | 2286 KB / 604 KB | 318 / 66 / 723 KB | Plus adapters; lit, valtio |
| `@safe-global/protocol-kit@8.0.11` | 1594 KB / 310 KB | 213 / 14 / 485 KB | For scale; the Safe agent owns this decision |
| `@rainbow-me/rainbowkit@2.2.11` | not measured | not measured | Peer deps `react >=18`, `wagmi ^2.9`: **out** |
| `connectkit@1.9.2` | not measured | not measured | Peer deps `react 17/18`, `wagmi 2`; styled-components, framer-motion: **out** |

Findings that change the picture:

- `@walletconnect/ethereum-provider` lists `@reown/appkit` as a direct dependency, and `dist/index.js` does `await import("@reown/appkit/core")` for the QR modal, throwing "please install @reown/appkit" otherwise [P]. `showQrModal` is deprecated in favour of AppKit [D]. Headless use via the `display_uri` event is documented [D]. The bundler must stub this import or it will pull in AppKit.
- The UMD build contains `new Function` 0 times, `eval(` 0 times and `WebAssembly` 0 times [P, string count]. So `unsafe-eval` and `wasm-unsafe-eval` look unnecessary for WC. Confirm in the browser.
- `@base-org/account` depends on `brotli-wasm` [P]; expect `wasm-unsafe-eval` if ever adopted [U].

### 2.2 Verdict per option

| Option | Verdict | Why |
|---|---|---|
| Hand-rolled EIP-6963/1193 | **Yes, core** | Covers every extension and every wallet in-app browser with zero third parties. Costs us the state machine and failure handling, specified in section 8 |
| WC via ethereum-provider, headless | **Yes, optional, lazy** | Only way to reach a wallet in another app without its browser, and for wallets with no deep link. 459 KB gz, so it must never load by default |
| Reown AppKit | No | Largest graph, wider CSP (`fonts.reown.com`, `api.web3modal.org`) [P], same license and relay, English-first third-party UI on a Dutch product. Saves perhaps a week of UI |
| wagmi core | No | Gives store and reconnect logic, but we need custom binding states anyway and WC would still come through it. Defensible alternative if the state machine proves costly; it would add 16 KB gz |
| RainbowKit, ConnectKit | No | React-bound (confirmed by npm peer deps) |

**Challenging the brief.** Is WalletConnect needed at launch at all? A desktop user without an extension can scan a QR that opens `https://link.metamask.io/dapp/<our-host>/wallet/handoff/<token>` in the wallet browser, sign there, and the desktop page updates. That is a QR of our own URL with no relay. It covers MetaMask and Trust and has no third-party availability risk. It does not cover Rainbow, Ledger Live, Safe mobile and similar, which is what the WC option is for.

### 2.3 Importmap viability

- **`bin/importmap pin viem`: does not work.** importmap-rails 2.2.3 posts to `api.jspm.io/generate` with `flattenScope: true` and downloads only the values of the returned `imports` map [P, read `lib/importmap/packager.rb`]. For viem that map has 24 entries, while the static graph has 116 files, and the entry is the unbundled `_esm/index.js`, whose relative imports will 404 once vendored [P for counts, inference for the failure; not run]. Do not spend time on this.
- **Runtime CDN pins (jspm, esm.sh):** rejected. Adds third-party script origins to `script-src` on a money page, for no benefit.
- **Vendoring esm.sh `?bundle` by curl:** works technically for viem (a single file with no imports [P]). WC's bundle additionally imports `/node/buffer.mjs`, `/node/events.mjs`, `/node/process.mjs` [P]. Rejected because it trusts a third party's build and cannot be reproduced from a lockfile.
- **The npm UMD:** first-party and prebuilt, no build step, but contains AppKit and is a classic script. Fallback only.
- **Recommended: vendoring step with esbuild.** Run by a developer or CI when updating; the outputs are committed and served by Propshaft. Rails deploy stays Node-free.

```
vendor/wallet-bundles/
  package.json, package-lock.json       # exact versions, npm ci --ignore-scripts
  entry-viem.js                         # named re-exports only
  entry-walletconnect.js
  stub-appkit.js                        # throws; replaces @reown/appkit/core
  build.sh
vendor/javascript/
  viem-2.57.11.js
  walletconnect-2.26.0.js
  uqr-0.1.3.js
```

```sh
npm ci --ignore-scripts
npx esbuild entry-viem.js --bundle --format=esm --target=es2022 --minify \
  --legal-comments=linked --outfile=../javascript/viem-2.57.11.js
npx esbuild entry-walletconnect.js --bundle --format=esm --target=es2022 --minify \
  --alias:@reown/appkit/core=./stub-appkit.js \
  --define:global=globalThis --inject:./node-shims.js \
  --legal-comments=linked --outfile=../javascript/walletconnect-2.26.0.js
```

`--ignore-scripts` keeps npm lifecycle scripts off the build machine. esbuild's own binary comes through an optional platform package, so check it still resolves [U]. Node shims (`buffer`, `process`) may be needed for WC [U: esm.sh injects them, so likely].

```ruby
# config/importmap.rb
pin_all_from "app/javascript/wallet", under: "wallet"   # own zero-dep code
pin "viem",          to: "viem-2.57.11.js",          preload: false
pin "walletconnect", to: "walletconnect-2.26.0.js",  preload: false
pin "uqr",           to: "uqr-0.1.3.js",             preload: false
```

CI re-runs the build and fails on a diff. `bin/importmap audit` (already in CI) only inspects pinned npm versions and may misread these names, so add `npm audit` in `vendor/wallet-bundles` [U].

### 2.4 Reown project ID, license, relay

- **Needed:** yes, for WC. Listed as required for the provider [D]. Not needed for injected wallets.
- **Free:** $0 tier: 1 project, 1 team member, 2.5M RPC calls/month, 500 authenticated or embedded MAU, self-custodial MAU "within acceptable limits" (undefined), overage "cut off at limit". Pro is $89/month for 7,500 MAU, with self-custodial MAU listed as unlimited [D: reown.com/pricing, price partly via search].
- **Secret:** no, it ships in the browser. Protect by setting the dashboard origin allowlist; an empty list allows all origins, `localhost` is always allowed, changes take 15 minutes [D].
- **License changed.** Everything from `@walletconnect/ethereum-provider` 2.21.9 (2025-09-18) on is under the WalletConnect Community License; 2.21.8 and earlier were Apache-2.0 [P]. Terms that matter [D, read in the tarball]:
  - Section 2b: all use "must connect to the proprietary Reown gateway infrastructure ... unless we explicitly approve".
  - Section 3: a commercial license is required above 2.5M RPC calls or **500 MAU, where MAU includes "a unique externally owned account that authenticates and connects to your app in a 30 day period"**. Thresholds determined in their sole discretion and changeable.
  - Section 2a: attribution notice and a copy of the license must ship with the product.
  - Section 1c: modifications are assigned to Reown.
- **Conflict to resolve with Reown or counsel:** the license counts connecting EOAs towards 500, while the pricing page calls self-custodial MAU "within acceptable limits" and applies 500 to "SIWX / SIWE enabled" apps. Whether our own SIWE over a WC session counts is unclear. Budget for Pro once WC users exceed a few hundred a month. Pinning 2.21.8 would get the Apache license but a stale client, and the relay's own terms still apply. Not recommended.
- **Is the relay permissionless? No.**
  - An anonymous WebSocket handshake gets HTTP 401 `{"error":"JWT is missing"}` [P]; the docs add 401/403 for missing or invalid project IDs [D].
  - The license mandates the Reown gateway [D].
  - An October 2025 governance post proposes a permissionless relayer program and describes today's relay as run by "a limited set of operators"; no evidence it was adopted [D for the post, S for the roadmap].
  - Service nodes may be run by multiple parties [S], but access is gated. There is no documented way to self-host for production [U].
- **Privacy.** Reown's policy lists for relay infrastructure: IP address, **full wallet address**, country and region, client ID, encrypted payloads, protocol metadata, user agent and SDK version [D]. Payloads are encrypted, but the IP-to-wallet link is visible to Reown. The policy makes Reown a processor for customers' end-user analytics and leaves consent and lawful basis to the dapp [D]. This needs a line in our privacy policy and a DPA check. Without `rpcMap` the provider sends reads through Reown's Blockchain API [D], so always set `rpcMap`. `pulse.walletconnect.org` is a telemetry endpoint in the bundle [P]; check whether it can be turned off [U].

## 3. Failure mode this design avoids

Free tier cut-off, a Reown outage or a license dispute must never stop members signing. With the handoff route, MetaMask, Trust and any extension still work when the relay is unavailable. Rabby's mobile app is a browser-only route anyway (section 6).

## 4. Binding wallet to user

### 4.1 Current state [P]

- `users.wallet_address` has a unique index, but **no controller writes it**, so there is no proof of control and presumably no data. Check production before dropping.
- The format validation allows mixed case, so the unique index does not stop the same address being stored in two casings.
- `accounts.wallet_address` is unindexed and its validation is commented out.
- `dapp_controller.js` mixes sidebar and wallet logic, reads `window.ethereum` directly on every page, shows a hardcoded `€150.25`, and its disconnect only changes text.
- `pages/home.html.erb` claims "MetaMask, WalletConnect, Coinbase Wallet" support that does not exist.

### 4.2 SIWE design: server-composed message

The client never supplies the message, so we need no parser and no `siwe` gem.

```
POST /wallet_challenges  { address, chain_id, purpose: "link" }
  -> server validates address format, builds the EIP-4361 text, stores it
  -> { id, message }
client: personal_sign(hex(message), address)
POST /wallets            { challenge_id, signature }
  -> atomically consume the challenge, verify signature against stored address and message
```

```
fundtogether.example wants you to sign in with your Ethereum account:
0xAbC...EIP55

Koppel deze wallet aan je FundTogether-account. Dit kost niets en verplaatst geen geld.

URI: https://fundtogether.example/wallets
Version: 1
Chain ID: 100
Nonce: <32 alphanumeric>
Issued At: 2026-11-08T20:00:00Z
Expiration Time: 2026-11-08T20:10:00Z
Request ID: <challenge id>
```

Requirements, with EIP-4361 as the basis [D] and the rest as design choices:

- **Domain:** from configuration (`config.x.wallet.siwe_domain`), never `request.host`, so a spoofed Host header cannot influence it. Wallets compare it with the requesting origin [D], which is the actual anti-phishing control. Note this is only as strong as each wallet's implementation; WC-connected wallets depend on metadata and Verify [U].
- **Nonce:** `SecureRandom.alphanumeric(32)`; spec minimum is 8 alphanumeric [D]. Single use via `UPDATE ... SET consumed_at = now() WHERE id = ? AND consumed_at IS NULL AND expires_at > now()` and check the row count. Bound to `Current.user` and `Current.session`.
- **Expiry:** 10 minutes. Consider mobile round trips before shortening.
- **Chain ID:** EOA recovery is chain-independent, so **do not force a network switch before linking**. For contract wallets the chain ID defines where ERC-1271 is resolved [D], and the link is valid only on that chain.
- **Purpose:** stored on the challenge and reflected in the statement, so a `link` signature cannot be replayed as `replace` or a later `login`.
- **Text:** keep it ASCII-safe. eth.rb correctly uses `bytesize` [P], but some wallets render or encode non-ASCII poorly [U]. Hex-encode for `personal_sign`.
- **Rate limit:** use Rails 8 `rate_limit` on challenges. Email the user on every link, unlink and replace.

**Signature verification order** (from EIP-6492 [D], adapted):

1. Cap total length (for example 4 KB) and validate hex. ERC-1271 signatures can be any length, so length alone does not reject them.
2. If it ends in the `0x6492...` magic suffix: deployless `eth_call` with the `ValidateSigOffchain` bytecode. Only needed if Base Account or similar undeployed smart wallets are in scope. viem's implementation is a reference [P]. **Skip at launch** on Gnosis; return a clear error.
3. Exactly 65 bytes: `ecrecover` first. On match, done. This also handles EIP-7702 delegated EOAs, which viem treats specially [P]. Never pass other lengths to eth.rb: `dissect` accepts longer input and treats the remainder as `v` [P].
4. Otherwise, `eth_getCode` on the message's chain; if code exists, call `isValidSignature(hash, sig)` and expect `0x1626ba7e`. If there is no code, reject.

ERC-1271 results can change with on-chain state, and the spec says to invalidate sessions accordingly [D]. Since we only link, re-check at use time: the Safe tx verification path, not the link, decides.

### 4.3 Ruby: eth.rb vs siwe gem

| | `eth` 0.5.18 | `siwe` 2.0.0 |
|---|---|---|
| Last release | 2026-10-01 [P] | 2022-05-09; repo last pushed 2023-07 [P] |
| Ruby | `>= 3.0, < 5.0` [P] | `>= 2.5`, depends on `eth ~> 0.5.1` [P] |
| Function | `personal_recover`, `recover_typed_data`, `verify`, `Client#is_valid_signature`, ABI, JSON-RPC [P] | Regex parser and EOA-only `verify`. `verify(signature, domain, time, nonce)` **skips the domain and nonce checks when passed nil** [P], and has no ERC-1271 or 6492 |
| Native deps | `rbsecp256k1` 6.0.2, `keccak`, `scrypt`; also `bls12-381`, `httpx`, `openssl` gem [P] | Same, through eth |

**Use eth.rb, not siwe.** Its `to_recovery_id` accepts `v` of 0/1 and 27/28 [P], which covers Ledger-style output. Deployment cost: the Dockerfile's build stage has `build-essential pkg-config` but rbsecp256k1 also lists `automake libtool` and more [P], and it fetches libsecp256k1 at build time unless `--with-system-libraries` is passed. **Add those packages to the build stage** and test the image; the runtime stage needs nothing extra if statically linked [U]. A heavy dep tree for one function, but the Safe work likely wants ABI and RPC anyway. Coordinate with the Safe agent.

### 4.4 Data model

```ruby
create_table :wallets do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :address, null: false          # lowercase canonical; EIP-55 for display
  t.string  :kind, null: false, default: "eoa"  # eoa | contract | passkey_signer (later)
  t.bigint  :chain_id                      # NULL for eoa, required otherwise
  t.string  :label
  t.datetime :verified_at, null: false
  t.datetime :revoked_at
  t.timestamps
end
# One active owner per address (per chain for contract wallets):
add_index :wallets, "address, (COALESCE(chain_id, 0))", unique: true,
          where: "revoked_at IS NULL", name: "idx_wallets_active_address"

create_table :wallet_challenges do |t|      # uuid id
  t.references :user, null: false; t.references :session, null: false
  t.string :purpose, :address, :nonce, null: false
  t.bigint :chain_id, null: false
  t.text :message, null: false
  t.datetime :expires_at, null: false; t.datetime :consumed_at
end
```

- **Multiple wallets per user:** yes. People replace wallets and hold a desktop and a phone wallet.
- **One address, one user:** yes, globally. Otherwise two members could present the same owner, or one person could appear as two members and inflate their voting weight.
- **One owner per Safe per user:** enforced by the app, because the chain cannot know two addresses belong to one person. A user with two owner wallets on one Safe gets two votes.
- **Migration:** do not copy `users.wallet_address` as verified; it was never proven. Drop the column after confirming no meaningful data. `short_address` and `_user_menu` must change.

### 4.5 What a replaced wallet means for Safe ownership

**Linking a new wallet changes nothing on-chain.** The database is a pointer; `getOwners()` is the truth. So:

- Keep the owner on the membership: `account_memberships.owner_wallet_id` + `owner_confirmed_onchain_at`. Coordinate with the Safe agent.
- **Replacement flow:** (1) password re-entry, fresh session; (2) prove the new wallet with `purpose: replace`; (3) propose `swapOwner(prev, old, new)`, needing the threshold; the old wallet can sign if still available; (4) reconcile against `getOwners()`/events; only then point the membership at the new wallet.
- **Lost wallet:** remaining owners vote it out. This is a real recovery path but works only if the threshold can still be reached. A 2-of-2 with one lost key, or a 1-of-1, has no recovery and the app cannot help. **Say this at Safe creation, and prevent such configurations by default** (for example, refuse thresholds that leave no margin for one lost signer, or require acknowledgement).
- **Compromised wallet:** revoking in the app does nothing on-chain; the attacker still counts towards the threshold until swapped. UI must state this and prioritise the swap.
- **Unlink:** block while the wallet is an on-chain owner of any Safe.
- Members leaving a group: same swap or `removeOwner` with threshold check.

## 5. Onboarding people without a wallet

### 5.1 Ownership and dependency, honestly

| Option | Who controls keys | Vendor dependency | User risk | Cost | On Gnosis |
|---|---|---|---|---|---|
| Seed-phrase EOA (MetaMask, Rabby, Trust) | User, fully | None; portable to any wallet | Highest: seed loss, phishing, confusion | Free | Yes; MetaMask needs network added [S] |
| Passkey Safe owner | User's device or synced keychain | **Bound to our domain** through the WebAuthn RP ID [U, standard behaviour; S for Candide] | Device loss; recoverable by co-owners | Free contracts; signer deployment gas | Deployed [P] |
| Base Account / Coinbase Smart Wallet | User, by passkey; "users hold their own keys" [D] | Coinbase SDK and signing UI; docs have already moved and renamed twice [D] | Low UX risk | Free | **Not listed** [S] |
| Privy | Key reconstructed in vendor enclave from Shamir shares, under auth and policy checks [D] | High: enclave and API must be up. Docs read do not state export or continuity if Privy stops [D] | Vendor | Free to 499 MAU, then $299 to 2,499, $499 to 9,999 [D] | Not checked |
| Dynamic | Conflicting reports on model [S]; now at Fireblocks (`dynamic.xyz/pricing` 301-redirects there) [P] | High | Vendor | No free live tier; $249/month to 5,000 MAU, and their page contradicts itself on overage [D] | Not checked |
| MetaMask Embedded (ex-Web3Auth) | Described as non-custodial, distributed key infrastructure [D]; Shamir with reconstruction [S] | Medium to high | Vendor | Free 1,000 MAW, then from $69 [S] | Not checked |

Embedded wallets are the least "ordinary people pooling money non-custodially" story even when technically non-custodial: if the vendor and the login method both fail, access fails. They also reduce the honest meaning of "you own this". Their React-first SDKs also fight this stack: `@privy-io/react-auth`, `@dynamic-labs/sdk-react-core` [P]; JS-core variants exist (`@privy-io/js-sdk-core`, `@dynamic-labs-sdk/client`) but are heavy [P]. **Skip at launch.** Whether a vendor-operated enclave model affects the app's regulatory position under MiCA is a question for the legal track, not asserted here.

### 5.2 Safe passkey module status

- **Audits:** v0.2.0 by Certora; v0.2.1 had a Hats Finance competition with three low findings [P, repo], plus a Nethermind Security report added 2026-09-02 [P, commit]. Listed on Safe's audit page [D].
- **Deployments:** v0.2.1 `SafeWebAuthnSignerFactory`, shared signer and Daimo verifier are on chains 1, 100, 8453, 84532, 10, 42161, 137, 11155111 per `safe-modules-deployments@3.0.14`; **not on Chiado (10200)** [P]. Test on Sepolia or Base Sepolia.
- **FCL verifier:** removed from the repo in March 2026 for known non-critical bugs, as EIP-7951 makes it unnecessary [P]. Do not use it; use precompile plus Daimo fallback.
- **Precompile, live test [P]:** `eth_call` to `0x100` with a valid P-256 vector today returned `1` on **Gnosis, Chiado, Base, Base Sepolia, Arbitrum, Optimism, Polygon, Ethereum, Sepolia, Celo**. Gnosis activated Fusaka on 2026-04-14 [S]. Availability is no longer the blocker.
- **4337 not required for group Safes:** Safe's passkey guide lists only protocol-kit and viem [D]. A passkey signer verifies through ERC-1271 inside a multi-owner Safe, so signatures can be collected off-chain and any EOA or relayer can execute [U, by design, needs a test]. protocol-kit has `isPasskeySigner` handling in `signHash` [P].
- **Safe's own warning:** the `rawId` and coordinates must be stored persistently; losing them means losing access to the passkey and the Safe; always combine with other authentication [D]. Social recovery module v0.1.0 is **not** deployed on Gnosis or Base [P].

### 5.3 Base Account / Coinbase

Networks found: Base, Arbitrum, Optimism, Zora, Polygon, BNB, Avalanche, Ethereum; **no Gnosis** [S; the first-party CDP overview does not list networks]. Also the Base app, the renamed Coinbase Wallet, preconfigures no Gnosis and tells users to move assets on unsupported networks to another wallet after 2026-08-15 [S: help.coinbase.com snippet; the page returned 403]. **So on Gnosis, do not list Coinbase/Base as a wallet option.** Its contract wallets would also need ERC-6492 and contract-signature handling for Safe ownership.

### 5.4 Is account abstraction justified at launch?

**No, later.** Reasons:

- The hardest risk in a passkey path is not contract maturity. **A passkey only works on the RP ID's domain.** If FundTogether disappears or loses its domain, members cannot use that signer anywhere else. An EOA moves to any wallet in minutes. Related-origin requests only help across domains we control [U]. Honest non-custodial messaging must address this; co-owner swap is the exit.
- We would hold public-key data whose loss locks users out, so a new critical data store.
- WebAuthn in wallet in-app browsers and social webviews is unreliable [U].
- Needs a relayer or a co-owner EOA paying gas, which depends on the gas decision from another agent.
- It is a substantial second signing path while the first is untested with real users.

**Why it stays attractive:** for many ordinary users, seed phrases are the single biggest drop-off and loss risk. So gather data. **Decision trigger for phase 2:** measure onboarding completion and support load on the guided path; pilot if more than about a third drop out at wallet setup (a proposed threshold, not a benchmark). Pilot rule: a passkey owner only ever in a group Safe with enough other owners to swap it out.

**Seam to keep now:** `wallets.kind`; a signer interface in the JS layer so a "WebAuthn signer" can later implement `signSafeTx(hash)`; server verification that dispatches on `kind`; and a domain we commit to keeping.

## 6. "Get a wallet" guided path

Route by device. Do not show a long list.

| Context | Primary | Mechanism | Evidence |
|---|---|---|---|
| Desktop, extension detected | Detected wallets via EIP-6963 | Injected | [D] |
| Desktop, none | "Use your phone" QR handoff; secondary "Install Rabby or MetaMask" | Handoff | Design |
| iOS/Android, no wallet | Install MetaMask, then return via deep link | `https://link.metamask.io/dapp/{host}/...` | [D] |
| Mobile, has Trust | `https://link.trustwallet.com/open_url?coin_id=60&url={encoded}` | Reports of deep-link failure on iPhone [S]; test | [S, docs redirect now] |
| Mobile, Rabby | Instruct: open URL in Rabby's built-in browser. **Rabby Mobile does not support WalletConnect** [S: official support.rabby.io snippet]; no documented deep link found | Manual | [S] |
| Mobile, Coinbase | `https://go.cb-w.com/dapp?cb_url={encoded}`, only if chain is supported | Deep link | [S] |
| Other wallets, WC enabled | QR or `wc:` link; `link.trustwallet.com/wc?uri=` for Trust | WC | [S] |
| Social webview (Instagram, Telegram, WhatsApp, Facebook) | "Open in Safari/Chrome" instruction | No provider, deep links unreliable | [U] |

Choice: **MetaMask as the default recommendation** (only one here with a current first-party deep-link doc plus WC on mobile); **Rabby on desktop** (Gnosis preconfigured [S], clear transaction previews [U]). Trust's Gnosis support is **unverified**; test before listing.

**Handoff token:** wallet browsers have separate cookies, so the user would otherwise have to log in with a password inside a wallet browser.

- `/wallet/handoff/:token`: single use, 5 minutes, hashed in the database.
- Scope: this flow only (the challenge or one Safe signing request), not a full session. It must not reach the rest of the app.
- Confirmation screen shows the user's name and what will happen.
- Desktop page updates through a Turbo Stream, or polling.
- Risk: it trains users to open links in wallet browsers. Mitigate by only ever issuing these from a logged-in page, never email, and by saying so in the guidance.

**Guide steps in Dutch, one per screen:** what a wallet is and why FundTogether cannot recover it; install from the official store link (phishing-safe, verified links only, never search ads); write down the recovery phrase on paper; we will never ask for it; back to us; add the network if needed; sign a free test message (linking) and read back the address. Before the first real Safe involvement, repeat a test signature. Add a checkbox acknowledging "if I lose this and my group cannot replace me, the money is out of reach".

## 7. SIWE login or linking only?

**Linking only at launch. Add a step-up use. Consider login later only on demand.**

- Email and password stays regardless, because invitations, resets and notifications need email. So SIWE login adds no capability, just a second way in.
- A wallet compromise should not also become an app takeover. The app shows members and payments, and can trigger proposals; separating factors is useful.
- Users with only a wallet would have no recovery of app access.
- Reduces work: session invalidation for ERC-1271, plus a login path to harden.
- People who must sign in a wallet browser are handled by the scoped handoff token instead.

**Step-up use now:** require a fresh wallet signature for high-risk settings changes where a wallet is linked, in addition to the password. If login is later wanted: existing linked wallets only, never signup, same challenge table with `purpose: "login"`, and only after a linked email.

## 8. Wallet layer state machine

### 8.1 Structure

```
app/javascript/wallet/session.js     singleton, survives Turbo Drive visits
app/javascript/wallet/discovery.js   EIP-6963 listener, legacy window.ethereum fallback
app/javascript/wallet/errors.js      normalises wallet errors
app/javascript/wallet/chains.js      chain params from a server-rendered meta tag
app/javascript/wallet/walletconnect.js  dynamic import("walletconnect"), only if enabled
app/javascript/controllers/wallet_controller.js  thin view; subscribes on connect, unsubscribes on disconnect
```

Controller values from the server: `linkedAddresses`, `chainId`, `wcEnabled`. Sidebar logic moves out of `dapp_controller.js` and that controller is deleted.

**Two orthogonal parts:** connection state is explicit; binding status is **derived**, never stored, so it cannot drift.

```js
function status({ state, address, chainId }, { linked, requiredChainId, requiresChain }) {
  if (state !== "connected") return state
  if (!linked.includes(address))        return linked.length ? "address_mismatch" : "unlinked"
  if (requiresChain && chainId !== requiredChainId) return "wrong_network"
  return "ready"
}
```

`requiresChain` is per action: false for linking, true for Safe signing. An unknown new address gets `unlinked`-style behaviour: never auto-link. `address_mismatch` and `unlinked` differ only in copy.

### 8.2 States and transitions

| State | Event | Next | Effect or UI |
|---|---|---|---|
| `idle` | `init` | `discovering` | Register 6963 listener **before** dispatching request; keep it for the page lifetime [D] |
| `discovering` | 300 ms elapsed, remembered rdns present | `restoring` | Silent `eth_accounts`; never prompt |
| `discovering` | WC hint in localStorage | `restoring` | Dynamic-import WC, read `provider.session` |
| `discovering` | Providers, no memory | `disconnected` | Show picker |
| `discovering` | None | `no_wallet` | Late announces still accepted; guide by device |
| `restoring` | Accounts non-empty | `connected` | |
| `restoring` | Empty, error, or expired session | `disconnected` | Clear hint silently |
| `no_wallet` | Late `announceProvider` | `disconnected` | |
| `disconnected` | User picks injected | `requesting_accounts` | `eth_requestAccounts` |
| `disconnected` | User picks WC | `pairing` | Load bundle; `showQrModal: false`; `display_uri` to our QR or deep link |
| `requesting_accounts` | Accounts | `connected` | Store `{rdns, userId}` |
| `requesting_accounts` | 4001 | `disconnected` | Neutral "cancelled", no error styling |
| `requesting_accounts` | -32002 | `wallet_busy` | "Your wallet has a request open. Open it." |
| `requesting_accounts` | 60 s | stay + banner | Offer "open wallet" and reset |
| `wallet_busy` | Original promise resolves or user retries | `requesting_accounts` / `connected` | Retry only on explicit click |
| `pairing` | Connect resolved | `connected` | Set WC hint |
| `pairing` | Rejected, expired URI or closed | `disconnected` | Fresh URI on retry |
| `connected` | `accountsChanged([a])` | `connected` | Update; status recomputes |
| `connected` | `accountsChanged([])` | `disconnected` | Locked or revoked |
| `connected` | `chainChanged` | `connected` | Parse hex; recompute |
| `connected` | User clicks Switch | `switching_chain` | `wallet_switchEthereumChain` |
| `connected` | Action starts (sign) | `awaiting_signature` | Snapshot `{address, chainId, opId}` |
| `connected` | `disconnect` 4900, WC `session_delete` | `disconnected` | Clear hint; UI says session ended |
| `switching_chain` | Success or `chainChanged` | `connected` | |
| `switching_chain` | 4902 | `adding_chain` | `wallet_addEthereumChain` [D for 4902] |
| `switching_chain` | 4001 | `connected` | Remains `wrong_network`; explain |
| `switching_chain` | 4200, 4100, WC "unsupported chain" | `connected` | Instruction: change network in the wallet, or reconnect |
| `adding_chain` | Success | `switching_chain` | Some wallets also switch; re-read `eth_chainId` |
| `adding_chain` | 4001 or error | `connected` | Explain |
| `awaiting_signature` | Result, snapshot unchanged | `submitting` | Client-side recovery check, POST |
| `awaiting_signature` | `accountsChanged` or `chainChanged` | `stale` | Requests cannot be cancelled, so ignore any later result via `opId` |
| `awaiting_signature` | 4001 | `connected` | Neutral |
| `awaiting_signature` | -32002 | `wallet_busy` | |
| `awaiting_signature` | 45 s, 120 s | stay + banner | "Open your wallet"; then offer reset. On WC: reconnect socket when tab regains focus |
| `stale` | User restarts | `connected` | New challenge |
| `submitting` | 2xx | `connected` | Turbo Stream updates view |
| `submitting` | 4xx: expired, consumed or mismatch | `connected` | Specific copy, restart |
| any | Logout | `disconnected` | Clear hints; WC `disconnect()`, so a shared device keeps nothing |

Add `in_app_blocked` as an overlay when the UA matches known social webviews and no provider exists.

### 8.3 Error normalisation

| Code or signal | Meaning | Source | Handling |
|---|---|---|---|
| 4001 | User rejected | [D] EIP-1193 | Neutral copy, no retry prompt |
| 4100 | Unauthorized | [D] | Re-request accounts |
| 4200 | Unsupported method | [D] | Fall back, or explain |
| 4900, 4901 | Disconnected, chain disconnected | [D] | Reconnect |
| 4902 | Chain not added | [D] MetaMask | Add chain |
| -32002 | Request already pending | [U] MetaMask convention | `wallet_busy` |
| -32603 with `data.originalError.code` 4902 | MetaMask mobile wrap | [U] memory, docs read do not mention | Unwrap before matching |
| WC 5000-range and message matching /reject/i | Wallet-specific rejections | [U] | Treat as 4001; log raw |

### 8.4 Turbo and persistence

- **Provider across Turbo Drive visits:** JS modules are not re-evaluated, so `session.js` keeps provider, listeners and WC client. Attach provider listeners once in the singleton, **never in `connect()`**, or they multiply with each visit. Stimulus connects and disconnects freely; it only subscribes to the session.
- **Page cache:** on `turbo:before-cache` clear QRs, banners and sensitive UI so previews do not show stale states. Mark the wallet pill `data-turbo-permanent` to avoid flicker.
- **Full reload:** module state is lost. Restore through `eth_accounts`, which should not prompt.
- **What is stored:** `localStorage` `ft.wallet = {kind, rdns, userId}`. Compare `userId` before restoring. `uuid` is page-lifetime only [D], so use `rdns` only as a selection hint: it is self-attested and must not be used for trust or feature detection [D]. WC persists via IndexedDB itself (`idb-keyval` in graph) [P].
- **Icons:** render only as `<img src=data:...>` [D]. Treat `name` and `icon` as untrusted. Watch for duplicate uuids [D].
- **Legacy fallback:** in-app browsers may expose `window.ethereum` without 6963 [U]. Treat as "Browser wallet".
- **Requests:** serialise. Only one wallet prompt at a time from this layer.
- **The server decides.** Client state is presentation. Every sign result is verified server-side against the expected owner and chain.

### 8.5 Case-by-case

- **Connected differs from linked:** never auto-switch or auto-link. "You are using 0xAb..12, your linked wallet is 0xCd..34. Switch in your wallet, or link this one." On signing, block entirely if not the membership owner.
- **Mid-flow account switch:** `stale`, as above; server rechecks with the challenge's stored address.
- **Mobile WC:** the WebSocket can suspend while the wallet app is foregrounded, and browsers restrict navigation not tied to a user gesture [U]. So generate the URI **before** the tap, deep-link inside the click handler, and on `visibilitychange` re-check session and pending state.
- **Gnosis add params:** `{chainId:"0x64", chainName:"Gnosis", nativeCurrency:{name:"xDAI",symbol:"XDAI",decimals:18}, rpcUrls:["https://rpc.gnosischain.com"], blockExplorerUrls:["https://gnosisscan.io"]}`. Chain ID and RPC [P]; explorer [U]. Wallets may warn about RPC URLs.

## 9. Content Security Policy

### 9.1 Today [P]

No active CSP: the initializer is entirely commented out, although `csp_meta_tag` is present. Blockers:

- `<script src="https://cdn.tailwindcss.com">` in the layout: unpinned, redirects to `/3.4.17` (v3), 407 KB of JS.
- Inline `<style>` in the layout.
- Inline `<script>` in `transactions/new.html.erb`.
- Inline `onclick` in `invitations/success.html.erb`, which also interpolates a URL into JS.
- Inline `style=` in `users/index.html.erb` (mailers are unaffected by the page CSP).

### 9.2 Can the CDN Tailwind go? Yes, and it must

`tailwindcss-rails ~> 4.4` is installed, `Procfile.dev` runs the watcher, and `app/assets/builds/tailwind.css` is built (33 KB) but **no view links any stylesheet** [P]. Everything visible is rendered by the v3 CDN script. Moving means **v3 to v4**, so do not just swap the tag. Usage counts in views [P]:

- `flex-shrink-*` 16 and `bg-opacity-*` 4: removed in v4 [U: from the upgrade guide, from memory]; replace with `shrink-*`, `bg-black/50`.
- `shadow-sm` 22 and `outline-none` 2: renamed or changed meaning [U].
- bare `border` 74: default colour changes in v4 [U]; `border-gray-*` 71 explicit uses help.
- No `tailwind.config` in use [P], so the migration is mechanical. Consider Tailwind's upgrade tool; visually check every page. Budget half a day to a day. Move layout `<style>` rules to `application.css`.

### 9.3 Policy

```ruby
Rails.application.configure do
  config.content_security_policy do |p|
    p.default_src :self
    p.script_src  :self
    p.style_src   :self
    p.img_src     :self, :data              # EIP-6963 icons are data: URIs
    p.font_src    :self
    p.connect_src :self, *wallet_connect_src  # see below
    p.frame_src   *wallet_frame_src         # :none when WC is off
    p.frame_ancestors :none
    p.object_src  :none
    p.base_uri    :self
    p.form_action :self
    p.report_uri  "/csp-violation-report"   # start report-only
  end
  config.content_security_policy_nonce_generator = ->(_req) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_report_only = true
end
```

- **Do not copy the commented `request.session.id.to_s` generator.** This app authenticates through a signed `session_id` cookie (`concerns/authentication.rb`), not the Rails session, so `request.session.id` may be nil or unstable and yield an empty nonce [U; inference from code]. Per-request is the default the Rails guide calls good; it breaks ETag-based conditional GET [D]. If any page depends on `fresh_when`, reconsider per-page.
- **Importmap with nonces: works.** importmap-rails 2.2.3 adds the nonce to the inline importmap, `javascript_import_module_tag` and modulepreload links [P].
- **Turbo: works.** turbo-rails 2.0.23 strips nonces when comparing head elements (`elementWithoutNonce`) and applies the `csp-nonce` meta to activated scripts [P], so per-request nonces should not force full reloads. Confirm in the browser. Removing all inline body scripts makes this moot anyway.
- **`connect-src`:**
  - Injected-only: `:self` + the RPC host if the browser reads the chain directly. Wallet requests go through the extension, not page fetch [U]. **Prefer reads via Rails**, so no RPC key leaves the server and no RPC host appears here.
  - WC on: `wss://relay.walletconnect.org`, `https://rpc.walletconnect.org` (unless `rpcMap` fully replaces it), `https://pulse.walletconnect.org`, `https://verify.walletconnect.org`, `https://verify.walletconnect.com`. From strings in the bundle [P]. **Finalise from report-only logs.** Docs examples still show `relay.walletconnect.com` [D].
- **`frame-src`:** `https://verify.walletconnect.org https://verify.walletconnect.com` if the provider's Verify iframe loads; `https://secure.walletconnect.org` should only be needed for AppKit's embedded wallet, which we do not use [P for strings, U for need].
- **`script-src`:** `:self` + nonce. No `unsafe-eval`, no `unsafe-inline`, no `wasm-unsafe-eval`, subject to the browser test.
- **Extensions and in-app browsers:** MV3 wallet injection generally does not depend on page CSP, but older or in-app injection might [U]. Test: MetaMask, Rabby, Trust in-app, MetaMask in-app, under the enforced policy, before leaving report-only.

## 10. Mobile signing: Safe EIP-712 over WalletConnect

**What we know:**

- protocol-kit defaults to `eth_signTypedData_v4`, then `adjustVInSignature` [P]. Its typed-data domain for the signing call is only `{ verifyingContract, chainId }` [P]. So no `name` shows in wallet UI: users see an address and a hash-like view. Our own page must show the human summary alongside.
- Alternatives in the kit: `eth_signTypedData_v3`, and a raw `signMessage` path (`eth_sign` signing method) [P]. **Fallback** when typed data is unsupported: `personal_sign` of the safeTxHash, adjusted v. This is blind signing; warn explicitly and don't enable by default.
- **WC requires the method in the session namespace.** `eth_signTypedData_v4` missing gives "Unsupported method"; declare `optionalMethods` explicitly: `personal_sign`, `eth_signTypedData_v4`, `wallet_switchEthereumChain`, `wallet_addEthereumChain` [S: wagmi discussion #2240 and issue #3012]; default is all EIP-1193-compatible methods [D]. Declare `optionalChains: [100]`.

**Reported incompatibilities.** All come from issue trackers; none were retested here and several are old.

| Wallet | Report | Mitigation |
|---|---|---|
| MetaMask extension | Domain `chainId` string read as hex, causing mismatch (#11830) [S] | Send number; viem does |
| MetaMask extension | Silent hang when domain chain is not in wallet (#18276) [S] | Ensure chain added and active first; timeout UI |
| MetaMask mobile | Warnings or failure when chain differs from active (#1551, #3385) [S] | Require active chain == Safe chain before signing |
| Trust extension | "ChainId Mismatch" on v4 (#376) [S] | Same |
| Ledger via MetaMask | `v` 0/1 forms [P, eth.rb handles] ; display limits [U] | protocol-kit adjusts; verify recovery server-side |
| Rabby mobile | No WC at all [S] | In-app browser route only |
| Contract-wallet owners | Return ERC-1271 signatures, not ECDSA [P for kit handling] | Refuse as owners at launch, or test explicitly |

**Rules for the layer:**

1. Before any Safe signature: assert `eth_chainId` equals the Safe's chain and the address is the expected owner.
2. After signature: recover locally, compare with the expected owner, then POST; the server recomputes `safeTxHash` itself and verifies again. This turns every wallet quirk into a clean error, not a bad signature stored.
3. Treat long waits as normal; never auto-retry a signature.

**A real device matrix is needed** before launch and **cannot be done here**: MetaMask iOS and Android (in-app and WC), Trust iOS and Android, Rabby in-app and extension, MetaMask extension, Ledger through MetaMask. Run on Sepolia or the chosen chain.

## 11. Exact packages

**JS, in `vendor/wallet-bundles/package.json`:**

| Package | Version | Published | Purpose | Load |
|---|---|---|---|---|
| `viem` | 2.57.11 | 2026-10-24 | Encoding, typed data, Safe | Lazy, signing pages |
| `@walletconnect/ethereum-provider` | 2.26.0 | 2026-10-08 | WC v2, headless | Lazy, only on user choice and project ID present |
| `uqr` | 0.1.3 (MIT) | 2026-04-03 | QR for handoff and WC | Lazy |
| `esbuild` (dev only) | 0.28.2 | 2026-08-08 | Vendoring | Never in production |

Why not latest: `viem` 2.57.17 was published today. **Pin releases at least 14 days old** for supply-chain safety; npm incidents are recurring [S]. Update `viem` deliberately. If the Safe agent adds protocol-kit (8.0.10 is the last before this cutoff), its `viem ^2.52.2` range [P for 8.0.11] accepts this version; bundle together to avoid two viems.

**Not added:** `@reown/appkit`, `wagmi`, `mipd`, `rainbowkit`, `connectkit`, any embedded-wallet SDK, `siwe` gem.

**Ruby:** `gem "eth", "0.5.18"` (`>= 3.0, < 5.0`, repo is on 3.4.6). Docker build stage needs `automake libtool` and possibly more; check rbsecp256k1's README list and test the image.

## 12. What is needed from the user

| Item | When | Secret? | Notes |
|---|---|---|---|
| Chain decision | Now | n/a | Gnosis vs Base changes wallet list and 6492 scope |
| Production domain | Before SIWE ships | No | Goes into `siwe_domain`; passkey RP ID later |
| Reown project ID | **Only when enabling WC** | No, public | Free at dashboard.reown.com, needs an account; set origin allowlist; 1 project on free, so staging shares or uses a second account |
| Decision on Reown license | Before enabling WC | n/a | Accept community license, attribution, 500 MAU ambiguity; DPA; privacy policy line. Counsel if unsure |
| Server RPC URL with key | Only for ERC-1271 reads or production volume | **Yes**, Rails credentials | Public `rpc.gnosischain.com` answered `eth_call` today [P] but is unsuitable for production [U] |
| Test phones and wallets | Before launch | Test seeds only, never real | iOS and Android; Sepolia funds |

**No Privy, Dynamic, Web3Auth or Coinbase credentials needed.**

## 13. Testable without credentials

**Fully, in CI:**

- SIWE message format, challenge lifecycle, expiry, replay, wrong user, wrong session, purpose confusion, domain fixed by config, address case normalisation. Generate keys with `Eth::Key.new`, sign with real secp256k1 and verify.
- `v` 0/1/27/28, wrong length, wrong signer.
- ERC-1271 branch with stubbed JSON-RPC.
- Wallet model: active uniqueness, re-link after revoke, block unlink while owner.
- State machine in pure JS or Capybara system tests: inject a mock EIP-1193 provider that announces through `eip6963:announceProvider` and scripts 4001, -32002, 4902, `accountsChanged`, `chainChanged`, empty accounts, late signature after a switch.
- Turbo: visit several pages, assert listeners are not duplicated and session is retained; full reload restores silently.
- CSP report-only: run system tests and fail on violation reports.
- QR rendering and deep-link generation.

**Manually, no credentials, no accounts:** real extension (MetaMask or Rabby) on a test key, signing and network switching on Sepolia or Chiado; live precompile reads.

**Blocked without a Reown ID:** any real WC pairing; relay returns 401 without proper auth [P]. `localhost` is auto-allowed once an ID exists [D]. Until then, test WC only behind a mock of `display_uri`, `connect`, `session_delete`.

**Blocked without devices:** section 10's matrix and deep-link behaviour.

## 14. Sequence

1. Tailwind v4 migration; remove inline scripts and handlers; CSP report-only. Independently valuable.
2. `wallets` and `wallet_challenges`; server flow with tests; add Docker packages.
3. Zero-dep wallet layer + mock-provider tests; retire `dapp_controller`; correct home page claims.
4. Handoff route + get-a-wallet guide (MetaMask, Rabby, Trust after testing).
5. Vendored viem + Safe signing with the pre and post checks, built with the Safe agent.
6. Optional WC behind project ID; device matrix; CSP enforcing.
7. After launch data: passkey pilot decision.

## 15. Open questions and known gaps

- Target chain (blocking; other agent or team lead).
- Tree-shaken real size of viem and whether WC builds cleanly with the stub: requires running esbuild, not allowed here.
- WC `pulse` telemetry disablement and exact CSP set: confirm by running.
- Trust's Gnosis support, Trust deep links on iOS, MetaMask `originalError` wrap: unverified.
- Whether `-32002` is emitted the same across non-MetaMask wallets: unverified.
- Reown license MAU reading.
- Base Account network list: first-party confirmation not obtained; the pages have moved.
- Whether Safe's Transaction Service and Safe{Wallet} treat a WebAuthn signer as a first-class owner end to end: unverified; matters for the "exit" story.
- Tailwind v4 class changes: from memory, not re-read.

## 16. Sources

**Probed directly:**

- npm registry: `viem`, `@wagmi/core`, `@walletconnect/ethereum-provider`, `@reown/appkit`, `@rainbow-me/rainbowkit`, `connectkit`, `@base-org/account`, `@safe-global/protocol-kit`, `@privy-io/*`, `@dynamic-labs*`, `@web3auth/modal`, `uqr`, `esbuild`
- https://api.jspm.io/generate, https://esm.sh
- https://unpkg.com/@walletconnect/ethereum-provider@2.26.0/LICENSE.md
- https://unpkg.com/@reown/appkit@1.8.24/LICENSE.md
- https://unpkg.com/@safe-global/safe-modules-deployments@3.0.14/ (passkey JSON)
- https://relay.walletconnect.org (handshake), https://cdn.tailwindcss.com
- RPCs: rpc.gnosischain.com, rpc.chiadochain.net, mainnet.base.org, sepolia.base.org, arb1.arbitrum.io/rpc, mainnet.optimism.io, polygon-bor-rpc.publicnode.com, ethereum-rpc.publicnode.com, ethereum-sepolia-rpc.publicnode.com, forno.celo.org
- https://rubygems.org/api/v1/gems/eth.json, siwe.json, rbsecp256k1.json
- https://github.com/q9f/eth.rb, https://github.com/spruceid/siwe-ruby, https://github.com/etscrivner/rbsecp256k1
- https://github.com/safe-global/safe-modules/tree/main/modules/passkey
- Local: importmap-rails 2.2.3 and turbo-rails 2.0.23 gem source; repo files

**First-party docs read:**

- https://eips.ethereum.org/EIPS/eip-4361, /eip-6492, /eip-6963, /eip-1193
- https://reown.com/pricing, https://reown.com/privacy-policy, https://reown.com/faq
- https://docs.reown.com/cloud/relay, https://docs.reown.com/advanced/providers/ethereum
- https://governance.walletconnect.network/t/decentralized-relayer-network-and-incentive-framework/4115
- https://docs.safefoundation.org/security/audits, https://docs.safe.global/sdk/signers/passkeys
- https://docs.privy.io/security/wallet-infrastructure/secure-enclaves, https://www.privy.io/pricing
- https://www.fireblocks.com/dynamic-pricing, https://docs.metamask.io/embedded-wallets/
- https://docs.metamask.io/wallet/how-to/manage-networks/add-network/
- https://docs.metamask.io/metamask-connect/evm/guides/metamask-exclusive/use-deeplinks.md
- https://docs.cdp.coinbase.com/coinbase-wallet/overview, https://guides.rubyonrails.org/security.html

**Secondary or snippet only:**

- https://support.rabby.io/en/articles/14123218-how-to-connect-rabby-to-a-dapp
- https://help.coinbase.com/en-in/base/getting-started/upgrade-wallet (403 on direct fetch)
- https://docs.base.org/identity/smart-wallet/features/networks
- https://developer.trustwallet.com/dapps/mobile-optimize, https://docs.cdp.coinbase.com/coinbase-wallet/developer-guidance/mobile-dapp-integration
- https://github.com/wevm/wagmi/discussions/2240, https://github.com/wevm/wagmi/issues/3012
- https://github.com/MetaMask/metamask-extension/issues/11830, /18276
- https://github.com/MetaMask/metamask-mobile/issues/1551, /3385
- https://github.com/trustwallet/trust-web3-provider/issues/376
- https://status.quicknode.com/incidents/qzc59nbc51rb (Gnosis Fusaka date)
- https://help.gnosispay.com/hc/en-us/articles/39720952321428
- https://candide.dev/blog/safe-passkeys/, https://docs.candide.dev/wallet/plugins/passkeys
- https://www.openfort.io/blog/web3auth-alternatives (competitor blog)
- https://www.binance.com/en/research/projects/walletconnect (roadmap)

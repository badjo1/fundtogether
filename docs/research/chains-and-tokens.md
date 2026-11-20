# 02: Chains, tokens and protocol research for FundTogether

Measured 2026-11-08, about 18:40-19:30 CET. All on-chain work was read-only JSON-RPC with no transactions.

Evidence labels:
- **[M]** I measured it, on-chain or through a live API, in this session.
- **[P]** A primary source says so (the issuer, the project's docs, a regulator).
- **[S]** A secondary source says so (news, third-party docs).
- **[U]** Unverified: my inference or recollection, not confirmed.

Raw measurement scripts and output are in `chains/`.

Prices used [M]: ETH $2,230.84, POL $0.0894, xDAI $1.00 (CoinGecko). EUR/USD 1.1165 (frankfurter.dev, 2026-11-06).

## 1. Bottom line

**Default: Base + EURC. Medium confidence; Gnosis + EURe is a close second.** Gas cost does not decide this: each action on every L2 and Gnosis costs under 1.5 cents today. The deciding factor is ramp redundancy.

- Base is the only low-fee candidate where both native euro tokens exist, so it does not depend on one issuer's ramp.
- Gnosis + EURe is the better chain technically (fast finality, best public RPC, near-zero fees). But it has a single euro token and a single fiat route (Monerium). None of the three exchanges I checked lists EURe or xDAI.

**The choice should flip to Gnosis + EURe** if Monerium is the primary ramp and agent(s) working on on-ramps confirm its onboarding is workable. See section 11.

**Findings most likely to change plans:**
1. **EURA is out.** Angle governance voted to wind it down; redemption ends 2027-03-01 [S]. Existing supply figures are residual.
2. **EURC is not native on Gnosis, Arbitrum, Polygon or OP.** It is absent from Circle's address list, which names Base and Ethereum among the shortlisted chains [P].
3. **Mt Pelerin is a compliance problem.** Its own page says it holds no EU MiCA authorisation and does not solicit EU clients [P]. Promoting it inside a Dutch-focused app needs legal review. It also does not mention iDEAL and does not support SEPA Instant [P].
4. **EURe has two addresses on Gnosis, Polygon and Ethereum, and V1 calls emit a Transfer on both.** An indexer that watches both will double count. A 9,000-block Gnosis window held 5,234 V2 Transfer logs and 3,604 V1 Transfer logs [M]; I did not pair them one by one. Index V2 only.
5. **Linking a Safe to Monerium has a lasting trust cost.** `burn` and `recover` accept the fixed-hash linking signature, callable by Monerium's system role, with no multisig approval from the Safe at that time [P, source code]. See section 6.3.
6. **Exchange withdrawals are mostly L1.** Bitvavo, Kraken and Bitstamp list EURC on Ethereum only [M/P]. Only Coinbase offers EURC on Base [M]. The Dutch market leader Bitvavo cannot send EURC to any L2.
7. **Gelato relay on the Safe SDK ended 2026-09-01** [P]. Free relay should not be part of the design.
8. **Safe Transaction Service keyless quota is 2 RPS and 5,000 requests per month** [P]. That is not a production budget.

## 2. Costs

Gas figures [M]:
- **Safe deploy:** `eth_estimateGas` on `createProxyWithNonce` for a 3-owner, 2-of-3 Safe L2 1.4.1 setup, with no transaction sent: 313,050 on Gnosis, Base, OP and Ethereum; 313,394 on Arbitrum; 338,650 on Polygon. Real Gnosis deploys sampled: median 282,407.
- **ERC-20 transfer:** `eth_estimateGas` from a real holder. EURe: about 72,200 to a new holder, about 55,200 to an existing one. EURC and native USDC: 62,772 and 45,415. Polygon USDC: about 78,800.
- **`execTransaction`:** one simple Safe token-transfer sample each: 84,593 (Gnosis), 100,827 (Arbitrum). I use 101,000 everywhere. Other chains had no matching sample in the window, so this figure is an extrapolation [U] for them.

Monerium's docs quote 26,245 gas for a V2 transfer [P]. Actual totals are far higher, so do not budget from that number.

| Chain | Gas price now | Deploy (3 owners) | Token transfer | `execTransaction` | L1 data fee |
|---|---|---|---|---|---|
| Gnosis | 1.5e-8 gwei | under $0.001 (sampled max $0.0005) | under $0.001 | under $0.001 | none |
| OP Mainnet | 0.0010 gwei | $0.0007 | $0.00014 | $0.00023 | about $0.00001 per 600 bytes |
| Base | 0.006 gwei | $0.0042 | $0.0008-0.0010 (sampled median $0.0012-0.0033) | $0.0014 | about $0.00001 per 600 bytes |
| Polygon | 237-278 gwei | $0.0072-0.0084 | $0.0015-0.0020 | $0.0021-0.0025 | none |
| Arbitrum | 0.020 gwei | $0.014 | $0.0028-0.0032 (sampled $0.0018) | $0.0045 (sampled) | included in gas |
| Ethereum | 0.037-0.066 gwei | $0.026-0.046 | $0.005-0.011 (EURC sample median $0.061, max $0.27) | $0.008-0.015 | none |

**Stress cases, calculated rather than measured [U]:**
- Ethereum at 5 gwei: deploy $3.49, transfer $0.80, exec $1.13. At 20 gwei, four times that. L1 is cheap today, but no one controls the fee. Do not make it a default on today's price alone.
- Base at 0.05 gwei: deploy $0.035, exec $0.011.
- Gnosis wallets frequently overpay. At 1 gwei, a transfer costs about $0.00007.

**Conclusion:** among L2s and Gnosis, cost does not discriminate. Sponsoring 1,000 contributions costs roughly $1 on Base and about $0.07 on Gnosis even at the overpaid rate.

## 3. Gas token and how a normal person gets it

| Chain | Gas token | Direct route for a Dutch retail user | Evidence |
|---|---|---|---|
| Gnosis | xDAI | No listing on Coinbase, Bitvavo or Kraken. Mt Pelerin lists it (with the section 1 compliance caveat). Otherwise swap from EURe, bridge, or use small faucets. | [M] Coinbase `/currencies/XDAI` NotFound; Bitvavo and Kraken asset APIs have no entry. Monerium's Safe guide tells users to use a faucet or swap EURe [S, snippet; page returned 404 when fetched]. |
| Base | ETH | Coinbase withdraws ETH on Base directly. Bitvavo's API lists ETH only on Ethereum. | [M] Coinbase and Bitvavo APIs |
| Arbitrum | ETH | Coinbase direct. Bitvavo L1 only. | [M] |
| OP Mainnet | ETH | Coinbase direct. Bitvavo L1 only. | [M] |
| Polygon | POL | Coinbase lists ETH on Polygon [M], POL not checked. Bitvavo POL via Ethereum network, fee 12 POL. | [M] |
| Ethereum | ETH | Every exchange. Bitvavo withdrawal fee 0.00036 ETH (about $0.80). | [M] |

A user who only receives EURC or EURe has no gas on any chain. **Assuming users can always pay gas is wrong** for ordinary users on every candidate. See section 8.

## 4. Finality and crediting contributions

Lag behind `latest`, two samples per chain [M]:

| Chain | Block time | `safe` lag | `finalized` lag | Crediting rule |
|---|---|---|---|---|
| Polygon | 1.5 s | no tag | 0-3 s | `finalized`. Docs claim 2-5 s milestones [P]. A Sept 2025 milestone bug delayed this 10-15 min [S]. |
| Gnosis | 5.06 s | 5 s | 190-195 s | `finalized` (about 3.2 min) |
| Base | 0.2 s | 12-17 s | 948-953 s | Show pending at `safe`; credit at `finalized` (about 16 min) |
| OP Mainnet | 2.0 s | 78-82 s | 1,006-1,010 s | Same (about 17 min) |
| Arbitrum | 0.29 s | 778-782 s | 1,058-1,062 s | `finalized` (about 18 min). `safe` is nearly as slow. |
| Ethereum | 12.05 s | 576 s | 960 s | `finalized` (16 min) |
| Sepolia | 12.72 s | 720 s | 1,104 s | Same, so tests wait about 18 min unless a test-mode threshold is used |
| Base Sepolia | 0.2 s | 120-125 s | 1,156-1,161 s | Same |

Notes:
- **Use the `finalized` tag, not a block count.** A block count hides the fact that L2 finality depends on L1. With `finalized`, a reorg should be impossible in normal operation, so the indexer need only handle exceptions.
- Crediting a small amount from `safe` on Base is a reasonable product risk [U], but "credited" and "final" should be separate states.
- L2 `finalized` means L1 finality of the batch, not the end of the 7-day fraud-proof window. Withdrawals to L1 need that window, but crediting a contribution does not [U].
- Base's block time measures 0.2 s. Many docs still say 2 s, so do not hard-code it. 50,000 blocks is only 2.8 hours.

## 5. Decentralisation and failure modes

| Chain | Model | Known interventions and outages | Assessment |
|---|---|---|---|
| Ethereum | PoS L1 | None relevant here | Strongest |
| Arbitrum One | Stage 1 optimistic rollup, permissionless BoLD proofs [S, ethbeat.org, formerly l2beat, undated] | Single sequencer [S] | Strongest L2 on paper |
| OP Mainnet | Stage 1, fraud proofs [S] | Single sequencer [S] | Good, but no euro token here |
| Base | Stage 1, fraud proofs [S] | Single Coinbase-run sequencer. 43 min halt Sept 2023, 33 min halt Aug 2025 [S]. | Acceptable. Funds are protected by L1, liveness depends on one company. |
| Gnosis | Own PoS L1 beacon chain | Validators adopted a soft fork, then a hard fork on 2025-12-22, to move about $9.4M frozen after the Balancer exploit. Non-upgrading operators faced penalties. It was contested [S]. | Independent, but has shown it will intervene for a good cause. Less Ethereum security than a rollup. |
| Polygon PoS | Own validators with Ethereum checkpoints | Sept 2025 finality bug fixed with a coordinated hard fork [S] | Sidechain trust model |

Base concentration to state plainly: with Base + EURC, Coinbase runs the sequencer and is the main ramp, and it has a close commercial relationship with Circle [U]. A transparent fallback is to withdraw on L1 or to self-submit through Base's L1 force-inclusion path (exact delay not checked [U]).

## 6. Stablecoins

### 6.1 Comparison

| Token | Issuer and regulator | MiCA (ESMA interim EMT register) | Freeze | Upgradeable | Decimals | Shortlist verdict |
|---|---|---|---|---|---|---|
| **EURC** | Circle Internet Financial Europe SAS, ACPR (FR) | Yes, authorised 2024-07-01 [M, ESMA CSV] | Yes. `blacklister` set, `isBlacklisted` and `pause` present [M]. Terms allow blocking at Circle's discretion [P]. | Yes, FiatToken proxy admin set [M] | 6 | Default |
| **EURe** | Monerium ehf, Central Bank of Iceland (IS) | Yes, white paper notified 2026-01-09 [M, ESMA CSV] | Yes, via `validator.isBan` [P source]. Plus `burn` and `recover`, see 6.3. | Yes. UUPS, owner is a 3-of-6 Safe [M] | 18 | Second. Primary if the Monerium route is chosen. |
| **USDC** | Circle, ACPR | Yes [M] | As EURC | Yes | 6 | Not a euro. Optional later for dollar-denominated funds. |
| **xDAI** | Native Gnosis gas token, bridged DAI/USDS backing [U] | Not an EMT; no entry [M] | No token-level blacklist [U]. Bridge and backing risk apply. | Native | 18 | Gas only. Dollar-denominated, wrong unit for euro funds. |
| **EURA** | Angle (decentralised) | No entry [M] | Protocol | Yes, admin set [M] | 18 | **Excluded.** Being wound down; 1:1 EURC redemption until 2027-03-01, then possible de-peg [S]. |
| EURCV | SG-Forge, ACPR | Yes [M] | Issuer controlled [U] | Proxy [M] | 18 | Ethereum only in this check. Not for launch. |
| EURAU | AllUnity, BaFin | Yes [M] | Issuer controlled [U] | Proxy [M] | 6 | Supply 272,899 [M]. Too small. |
| EURR | StablR, MFSA (MT) | Yes, issuer listed [M] | [U] | Proxy [M] | 6 | 17.1M on Ethereum [M]. Not for launch. |
| EURQ | Quantoz, DNB (NL) | Yes [M] | [U] | Proxy [M] | 6 | Exactly 5,000,000 supply on Ethereum [M]. Dutch regulator is attractive. Watch. |
| EURS | Stasis | **No entry** [M] | [U] | No 1967 slot [M] | 2 | Excluded: not MiCA-listed. |

Redemption rights differ in practice:
- **EURC:** all holders can redeem at par. Retail holders register via a form, are verified, and are paid in up to 5 business days; a stress event can defer it [P]. For ordinary people, selling on an exchange is more realistic.
- **EURe:** par redemption for holders who become Monerium customers and pass due diligence [P, white paper via search]. Monerium stated no fees in 2023 [P, dated]; current individual fees are unconfirmed [U].

### 6.2 Supply per chain, measured at `totalSupply()` [M]

| Token | Gnosis | Base | Arbitrum | Polygon | OP | Ethereum |
|---|---|---|---|---|---|---|
| EURe | 13,918,038 | **26,596** | 5,455,788 | 2,437,104 | not deployed [P] | 3,533,253 |
| EURC | not native [P] | **52,340,730** | not native [P] | not native [P] | not native [P] | 324,820,102 |
| EURA | 88,299 | 25,540 | 84,715 | 72,256 | 31,387 | 1,311,170 |
| USDC (native) | none [P] | 4.33B | 2.38B | 599M | 126M | 46.2B |

Gnosis also has bridged USDC.e (8.47M) and older bridged USDC (12.64M) [M]. They are not Circle native per Circle's list [P].

DEX liquidity [M, DexScreener, GeckoTerminal and Curve API snapshots; each has coverage gaps]:

| Token and chain | Depth | 24 h volume | Largest pools |
|---|---|---|---|
| EURC, Ethereum | $12.4M | $1.40M | Uniswap EURC/EURCV, EURC/USDC |
| EURC, Base | $3.17M | $2.58M | Aerodrome EURC/USDC, EURC/WETH |
| EURe, Gnosis | about $316k (GeckoTerminal). Curve EURe-3Crv $225k, may overlap. | $116k | Curve |
| EURe, Ethereum | $169k | $9.4k | Uniswap EURe/EURC |
| EURe, Arbitrum | $144k | $9.9k | Uniswap EURe/USDC |
| EURe, Polygon | none found | none found | Probably a data gap [U] |
| EURe, Base | none found | none found | Supply is only €26.6k |

Implication: EURe exit in size depends on Monerium burn-to-IBAN, not on the DEX market. A €50k fund cannot leave EURe on a DEX without visible slippage on any chain [U, calculated from pool depth]. EURC on Base can.

### 6.3 EURe V2 specifics [P: source at github.com/monerium/smart-contracts; M where noted]

- **Addresses:** Gnosis, Polygon and Ethereum each have a V1 "frontend" and a V2 proxy. Monerium's `/tokens` API returns only V2 for these chains, plus Base, Arbitrum, Linea and Noble [M]. It returned no EURe entry for Scroll or Camino, although the docs list both as live; neither is on the shortlist. `totalSupply` is identical on V1 and V2 [M], confirming one ledger.
- **Double events:** calls via V1 emit Transfer on both addresses [P]. I saw this in a real Gnosis tx: logs on V2 and on V1 [M, 0x9fd2bac4...e74]. Also, the validator contract emits its own log in that tx, so "one log per transfer" filters fail on EURe [M]. **Index by Transfer events on V2 only.** To read history before the switch: V1 logs until T (Gnosis 35,656,951; Polygon 60,733,237; Ethereum 21,419,972), V2 after [P]. FundTogether's new Safes have no pre-T history, so this should not arise.
- **Transfer hooks:** a normal `transfer` and `transferFrom` call `validator.validate(from, to, amount)`, an external call to a Monerium-controlled, replaceable contract [P]. There is no recipient callback on V2 `transfer`. `transferAndCall` (ERC-677) exists only through the V1 controller path [P]. Neither is ERC-777-style. Consequence: a `setValidator` by the owner could change transfer rules without a token upgrade. A failing validator reverts every transfer.
- **Permit:** V2 supports ERC-2612 [P], confirmed by `nonces()` on Gnosis, Arbitrum, Base and Sepolia [M]. There is no EIP-3009 [M].
- **Ownership:** the owner of each proxy read is a 3-of-6 Safe [M]; the same owner address on Gnosis, Base and Polygon, others on Arbitrum and Ethereum.
- **`burn` and `recover`:** callable by a `system` role, which docs describe as an **EOA** [P]. They require a valid signature by `from` on the fixed hash `0xb77c35c8...50f`, verified through `isValidSignatureNow`, including ERC-1271 [P]. This appears to be the "I hereby declare" linking message [U]. Docs say recover relies on "the initial signature provided by the wallet owner at linkage" [P].
  - **What this means for a linked fund Safe:** after linking, Monerium's system key may be able to burn or move the Safe's EURe without a fresh owner approval. This is my reading of the code [U on exact Safe flow], which legal and security should confirm with Monerium.
  - **Mitigation:** do not link the fund Safe by default. Contributors link their own wallets, then pay the Safe by normal ERC-20 transfer. Linking only when the group explicitly wants an IBAN on the Safe. A non-linked address has no such signature, though it remains subject to `validator` bans and upgrades.
  - **Keep in perspective:** Circle can also blacklist, and both tokens are upgradeable. It is a qualitative difference, not an argument that EURC is trustless.
- **Decimals:** 18 versus 6 for EURC. `Noble` EURe uses 6 [M]. Store raw integers plus the decimals for each token.
- **Audit:** Ackee audited V2 [P]; reports are in the repo's `audits/`.

## 7. Infrastructure

### 7.1 Public RPC and `eth_getLogs`, with real Transfer filter [M]

Burst test: 10 sequential `eth_blockNumber` calls; no errors on the working endpoints; p50 100-260 ms.

| Chain | Endpoint | Max range or limit seen | Notes |
|---|---|---|---|
| Gnosis | `rpc.gnosischain.com` | 50,000 blocks OK (35,533 logs). Fails at 50,000+ **results**. | Best measured. Server suggests a narrower range. Archive call at head-2M OK. |
| Gnosis | `rpc.gnosis.gateway.fm` | Same, faster | Good backup |
| Gnosis | `gnosis-rpc.publicnode.com` | 10,000-block limit (exact error at 10,001) | Third option. Limited state history. |
| Base | `base-rpc.publicnode.com` | 50,000 blocks (= 2.8 h) | Use this |
| Base | `mainnet.base.org` | **`eth_getLogs` returned 429 on 5 of 5 attempts**; `blockNumber` fine | Could be specific to this IP or a load-related limit [U] |
| Arbitrum | `arb1.arbitrum.io/rpc` | 100,000 OK. 500,000 timed out. | Good. Its state history is limited, but logs work. |
| Polygon | `polygon-bor-rpc.publicnode.com` | 10,000 | `polygon-rpc.com` returned 401 "tenant disabled" |
| OP | `mainnet.optimism.io` | 1,000 OK on busy USDC; 2,000 "response too large"; documented 10,000 range limit | Fails by size |
| OP | `optimism-rpc.publicnode.com` | 2,000 OK; 5,000 hit 20,000-result cap | |
| Ethereum | `ethereum-rpc.publicnode.com` | 5,000 OK; 10,000 returned 403 "personal token" | `cloudflare-eth.com`, `eth.llamarpc.com` failed |
| Sepolia | `ethereum-sepolia-rpc.publicnode.com` | 10,000; 50,000 "pruned history unavailable" | `rpc.sepolia.org` down, `sepolia.drpc.org` paid only |
| Base Sepolia | `base-sepolia-rpc.publicnode.com` | 50,000 | `sepolia.base.org` limited to 200 |
| Any | `*.drpc.org` | 100 OK, 500-1,000 rejected on free plan | Misleading "over 10000" error message; rate limited at times |
| Any | `1rpc.io/*` | 50 blocks | Too small for scanning |

Design rules for the indexer:
- Filter by `address` plus Transfer topic plus `to = Safe` so results stay small. All tests above were harder than that: unfiltered recipient, full token.
- Chunk at 2,000 blocks or less and handle errors by halving. Limits vary per provider and are not stable.
- Maintain at least two endpoints per chain and never depend on a single public URL. Over a 24 hour gap, Base needs about 432,000 blocks, 216 requests at 2,000 per chunk.
- Public RPCs have no SLA. A free personal API key is the likely eventual step [U].

### 7.2 Safe

| Item | Status |
|---|---|
| Transaction Service | **Live on all candidates** [M]: `api.safe.global/tx-service/{gno,base,arb1,pol,oeth,eth,sep,basesep,chi}`, version 6.14.0. |
| API access | Keyless: 2 RPS, 5,000 requests per month, then HTTP 429 [P]. Authenticated plans introduced Feb 2026 [S]. Free "Builder" tier mentioned only by a third party [U]. |
| Safe{Wallet} UI | Help article (April 2026) names Arbitrum, Optimism, Base, Gnosis and Polygon [S, search snippet]. The Safe client gateway returned 403 to me and the app page did not render, so I could not confirm directly. Ethereum support is well established [U]. |
| Sponsored tx | Gnosis: up to 5 per day, "limited time", via Gelato and funded by Gnosis, per help article updated 2026-05-08 [S]. But Safe SDK docs say Gelato relay is unsupported from 2026-09-01 [P]. **Status uncertain.** Do not depend on it. |
| Chiado | Only Safe `1.3.0+L2` at `0x3E5c6364...` is indexed [M]. No 1.4.1. Using it means testing against different code than production. |
| Sepolia, Base Sepolia | Same 1.4.1 addresses as production [from brief], and Transaction Service is live [M]. |

Consider the alternative to reduce Transaction Service dependence [U]: gather signatures in the app and submit `execTransaction` directly, using the service only for Safe{Wallet} visibility. Agent(s) working on the Safe integration should decide this.

### 7.3 Explorers

- **Etherscan family:** web UI free on all chains here. All chains are in `api.etherscan.io/v2/chainlist` [M]. Free API tier is 5 calls/s, 100k/day [P], but Etherscan cut coverage by about 10% and its table did not render, so I could not confirm which chains remain free [P/U]. My recollection is that Base and OP are among those cut [U]. Do not depend on explorer APIs; use RPC.
- **Blockscout:** open source. Instance API responded for Ethereum, Sepolia and Base Sepolia [M]. Base, Arbitrum and Polygon instances returned a Cloudflare 403 to my script. Gnosis and OP returned 301 [M]. Free API key: 5 RPS, 100k credits per day [P].
- For user links: Basescan or Base Blockscout; Gnosisscan or Gnosis Blockscout. Links are free. Scripted access is not reliable.

### 7.4 Wallet support

Not tested hands-on in this session [U]. EVM wallets generally support all six chains; Base, Arbitrum, OP and Polygon are often preconfigured, while Gnosis may need adding through a prompt. Worth a hands-on check with Dutch beginner users. Any `wallet_addEthereumChain` flow should be part of the onboarding either way.

## 8. Can a user always pay? Gas sponsorship without paid infrastructure

No. A user who holds only EURC or EURe has no gas. Circle's Paymaster is USDC-only, with a 10% surcharge on Arbitrum and Base [P]; EURC is only "planned" [P]. EIP-4337 options require a bundler, which is usually paid infrastructure [U].

Options without paid infrastructure, all using standard audited contract features:

| Mechanism | How | Cost and trust |
|---|---|---|
| **EIP-3009 `transferWithAuthorization`** on EURC [M: present on Base and Ethereum] | Contributor signs off-chain. Any relayer submits. Funds go directly to the Safe. | Best contribution path. Relayer cannot redirect funds, because recipient and amount are signed. Requires a small app-held gas wallet. |
| **ERC-2612 `permit` + `transferFrom`** on EURe and EURC [M] | Relayer submits permit and transfer. On EURe, two calls (needs a multicall or two txs). | Less clean than 3009. An approval is created, so be careful with allowance scope. **Does not work without a helper contract as one atomic call** [U]; two separate txs are safe if allowance is exact. |
| **Safe native refund** (`gasPrice`, `gasToken`, `refundReceiver` in `execTransaction`) | Executor is paid by the Safe in EURC or EURe. | No extra contract. All owners approve refund terms by signing. Execution is permissionless, so anyone can execute. |
| **Safe deploy payment** (`paymentToken`, `payment`, `paymentReceiver` in `setup`) | Deployer repaid from funds already at the counterfactual address. | Lets contributions arrive before deployment. Test carefully [U]. |
| **Small gas drip from the app** | The app sends a tiny native amount to each user. | Very cheap, but it is a sybil target. Limit per verified user. |

Recommendation:
- Use a **single low-balance relayer EOA**, holding gas only and never user funds. At today's fees, about €5 of ETH on Base covers roughly 2,000-5,000 transfers [calculated from estimated and sampled fees].
- Always allow the fallback: **the user can pay their own gas and any owner can execute**, so the app's relayer is a convenience, never a gatekeeper.
- Rate-limit the relayer. A relayer outage must not trap funds.

Note on regulation: relaying signed user transfers may raise classification questions. That is for the legal workstream [U].

## 9. On-ramp interplay

| Route for a Dutch user | Chain and token | Fiat in | Status |
|---|---|---|---|
| Monerium account and own IBAN | EURe on Gnosis, Base, Arbitrum, Polygon, Ethereum | SEPA / SEPA Instant, about 5 s including mint per Monerium [P]; iDEAL not mentioned [U] | Requires KYC per person. Whitelabel and OAuth plans need a partnership application; Private is self-service but has KYC/KYB [P]. |
| Coinbase | EURC on **Base** or Ethereum, or USDC on most chains [M] | iDEAL deposit-only, instant [S, Coinbase support] | Requires Coinbase account and KYC. Must also obtain ETH on Base. |
| Transak | EURC on Ethereum or Base [P] | Card, wallets, bank transfer; iDEAL and NL availability not stated [P] | Fees unstated |
| Bitvavo | EURC on **Ethereum only** [M], fee €0.95 | iDEAL [U] | No route to an L2. |
| Kraken | EURC on **Ethereum only** [P, updated 2026-06-02]; USDC includes Base | not checked | |
| Bitstamp | EURC on **Ethereum only** [M] | not checked | |
| Mt Pelerin | EURC on Base. No EURe anywhere [from brief]. | SEPA 1-2 days, card, Apple/Google Pay; no iDEAL listed; no SEPA Instant [P] | **No MiCA authorisation; does not solicit EU clients** [P]. Excluded as a promoted route until legal clears it. |

Matrix of independent euro-to-chain routes, excluding Mt Pelerin:

| Chain | EURC routes | EURe routes | Count |
|---|---|---|---|
| Ethereum | Coinbase, Bitvavo, Kraken, Bitstamp, Transak | Monerium | 6 |
| Base | Coinbase, Transak | Monerium | 3 |
| Gnosis | 0 | Monerium | 1 |
| Arbitrum | 0 | Monerium | 1 |
| Polygon | 0 | Monerium | 1 |
| OP | 0 | 0 | **0** |

**This matrix is the core reason for choosing Base over Gnosis.** It also shows Ethereum L1 is the real route-rich option; a Bitvavo user can reach an L1 Safe directly today, though fee-exposed.

A notable product option: a **Safe with its own Monerium IBAN** would let contributors make a normal bank payment, with EURe minted straight into the Safe at no gas to them [P for IBAN and mint concept; U for suitability]. It avoids wallet onboarding for contributors, which is a huge UX gain, and works on any EURe chain. Against it: one customer owns that IBAN and their KYC, contributors' identities may not map on-chain, there are the section 6.3 trust effects, and possible "pooled funds" regulatory implications. Needs legal review. This is the strongest argument for choosing the Monerium route, and if it proves viable, it may outweigh everything above.

## 10. One chain or several at launch?

**Launch one. Model many.**

- Multi-chain creates real burdens: separate RPC failover, gas wallets, tests and support content, a user sending to the right address on the wrong chain, and a fund with split balances. A Safe at the same address on another chain may be undeployed or have different owners; funds sent there could be stuck or unrecoverable without redeploying [U on specifics].
- Model `chain_id` and token address as immutable per-fund fields from day one, and put chain and token parameters in a config table. Avoid hard-coded decimals, block times or RPC URLs.
- One fund = one chain and one token. Accepting EURC and EURe in the same fund adds a swap question (Base EURe has no observed liquidity) and accounting complexity.
- Detect and warn about tokens sent to the Safe in a non-configured token or on a different chain, but do not auto-credit them.

## 11. Ranked recommendation

**Default mainnet**
1. **Base (8453).** Euro route redundancy, deepest L2 euro liquidity (€52.3M EURC, $3.2M DEX), low cost, Stage 1 security.
2. **Gnosis (100).** Better technically: 3 min finality, best RPC, near-zero fees, largest EURe supply. Single issuer and single ramp; no exchange presence; validators have intervened. Makes sense if Monerium is primary.
3. **Ethereum (1).** Most routes and strongest security, currently cheap, but fees are unbounded and unsuitable for €5 contributions in a spike.
4. **Arbitrum (42161).** Strong security model and RPC, EURe €5.5M, but no native EURC, so one euro route. Reasonable if a future reason favours it.
5. **Polygon (137).** One route, gas token awkward, sidechain model, primary public RPC URL broken at test time.
6. **OP Mainnet (10).** Technically fine, but **no native euro stablecoin** from either issuer. Excluded for a euro product.

**Additional chains:** none at launch. First addition is Gnosis + EURe, once the Monerium route is confirmed. Then possibly Ethereum + EURC for exchange users with large contributions.

**Testnet**
1. **Base Sepolia (84532).** Mirrors the production fee model and block time. Has the same Safe addresses, Transaction Service, Circle USDC and EURC, and Monerium sandbox EURe [M].
2. **Sepolia (11155111).** Same tokens and service, good second, and a better match if L1 is ever added.
- **Avoid Chiado** as the main testnet, due to Safe 1.3.0 only [M]. Test the Gnosis/EURe path on Sepolia or Base Sepolia using sandbox EURe.

**Default tokens**
1. **EURC** on Base for euro funds.
2. **EURe** as the alternative token/route, on Gnosis, or on Base if Monerium's Base onboarding checks out.
3. USDC is optional later. EURA is excluded, EURS is excluded, xDAI only as gas.

**What would change my mind**

| Evidence | New decision |
|---|---|
| Monerium grants OAuth or Whitelabel access, and onboarding is smooth for Dutch retail users | Gnosis + EURe as default, particularly if the Safe IBAN option is legally clean |
| Coinbase route tests badly: friction, EU limits, or EURC on Base blocked for Dutch users | Base loses most of its advantage; Gnosis + EURe |
| Bitvavo or Kraken adds EURC on Base | Base strengthens |
| Bitvavo-first users dominate research, and L1 gas stays under 1 gwei with exec under $0.25 | Consider Ethereum + EURC as default, with fee warnings |
| Another Base sequencer incident of multiple hours, or censorship event | Reconsider; Arbitrum or Gnosis |
| Circle blocks a retail-relevant address class, or Circle's retail redemption fails in practice | Weight EURe higher |
| Monerium confirms `recover`/`burn` does not apply to linked Safes in practice | Removes the main objection to linked fund Safes |
| Legal says relaying signed transfers makes the app a regulated service | Remove relayer; users pay gas; favours Gnosis's negligible cost |
| Gnosis or a stablecoin issuer launches native EURC there, with exchange support | Gnosis becomes clear first |

## 12. Verified addresses

Evidence for every row: `eth_getCode`, `symbol()`, `decimals()`, and `totalSupply()` read on 2026-11-08 [M]. Supply is human-readable.

Sources:
- **Mon** = `https://api.monerium.app/tokens` (production) or `https://api.monerium.dev/tokens` (sandbox)
- **MonV2** = `https://docs.monerium.com/contracts-v2/`
- **CirE** = `https://developers.circle.com/stablecoins/eurc-contract-addresses`
- **CirU** = `https://developers.circle.com/stablecoins/usdc-contract-addresses`
- **Mem** = address was from my recollection; symbol confirmed on-chain, no primary doc checked. **Do not treat as canonical without a further check.**

### Mainnet

| Chain | Token | Address | Dec | Supply | Source |
|---|---|---|---|---|---|
| Base | EURC | `0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42` | 6 | 52,340,730 | CirE |
| Base | EURe | `0xbf6e2966A9C3D99C9E4D069E04f7Bdb9C8aa762C` | 18 | 26,596 | Mon |
| Base | USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 | 4.33B | CirU |
| Gnosis | EURe V2 **use this** | `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430` | 18 | 13,918,038 | Mon, MonV2 |
| Gnosis | EURe V1, do not index | `0xcB444e90D8198415266c6a2724b7900fb12FC56E` | 18 | same ledger | MonV2 |
| Gnosis | USDC.e, not in Circle's list | `0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0` | 6 | 8,472,268 | Mem |
| Gnosis | WXDAI | `0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d` | 18 | 40,241,867 | Mem |
| Arbitrum | EURe | `0x0c06cCF38114ddfc35e07427B9424adcca9F44F8` | 18 | 5,455,788 | Mon |
| Arbitrum | USDC | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 6 | 2.38B | CirU |
| Polygon | EURe V2 **use this** | `0xE0aEa583266584DafBB3f9C3211d5588c73fEa8d` | 18 | 2,437,104 | Mon, MonV2 |
| Polygon | EURe V1, do not index | `0x18ec0A6E18E5bc3784fDd3a3634b31245ab704F6` | 18 | same ledger | MonV2 |
| Polygon | USDC | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | 6 | 599M | CirU |
| OP Mainnet | USDC | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | 6 | 126M | CirU |
| Ethereum | EURC | `0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c` | 6 | 324,820,102 | CirE |
| Ethereum | EURe V2 **use this** | `0x39b8B6385416f4cA36a20319F70D28621895279D` | 18 | 3,533,253 | Mon, MonV2 |
| Ethereum | EURe V1, do not index | `0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f` | 18 | same ledger | MonV2 |
| Ethereum | USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 6 | 46.2B | CirU |
| Ethereum | EURCV | `0x5F7827FDeb7c20b443265Fc2F40845B715385Ff2` | 18 | 145,270,323 | Mem |
| Ethereum | EURQ | `0x8dF723295214Ea6f21026eeEb4382d475f146F9f` | 6 | 5,000,000 | Mem |
| Ethereum | EURR | `0x50753CfAf86c094925Bf976f218D043f8791e408` | 6 | 17,143,033 | Mem |
| Ethereum | EURAU | `0x4933A85b5b5466Fbaf179F72D3DE273c287EC2c2` | 6 | 272,899 | Mem |

Monerium also lists Linea `0x3ff47c5Bf409C86533FE1f4907524d304062428D` [P, not called on-chain].

### Testnet

| Chain | Token | Address | Dec | Reported supply | Source | Faucet |
|---|---|---|---|---|---|---|
| Base Sepolia | EURC | `0x808456652fdb597867f38412077A9182bf77359F` | 6 | 14.5B | CirE | Circle (reCAPTCHA); CDP |
| Base Sepolia | USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | 6 | 89.3B | CirU | Circle (reCAPTCHA); CDP |
| Base Sepolia | EURe sandbox | `0x29F37F6adCa168B79B8d9567eab9BE3fBF21db85` | 18 | 1.11B | Mon | Simulated SEPA in sandbox |
| Sepolia | EURC | `0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4` | 6 | 68.4B | CirE | Circle (reCAPTCHA); CDP |
| Sepolia | USDC | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | 6 | 10.7T | CirU | Circle (reCAPTCHA); CDP |
| Sepolia | EURe sandbox | `0x67b34b93ac295c985e856E5B8A20D83026b580Eb` | 18 | 10.3B | Mon | Simulated SEPA in sandbox |
| Arbitrum Sepolia | EURe sandbox | `0xFdEed5cE7E281B4e0F163B70eBe2Cf0B10803b7B` | 18 | 21.6B | Mon | Simulated SEPA |
| Arbitrum Sepolia | USDC | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` | 6 | 68.9B | CirU | Circle |
| Chiado | EURe sandbox | `0x7a47605930002CC2Cd2c3c408D1F33fc2a18aB71` | 18 | 30.9B | Mon | Simulated SEPA |
| Polygon Amoy | USDC | `0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582` | 6 | 117B | CirU | Circle |
| OP Sepolia | USDC | `0x5fd84259d66Cd46123540766Be93DFE6D43130D7` | 6 | 47.4B | CirU | Circle |

Monerium Amoy EURe: `0xeD5D0B6C5BEFfDd607639094397C223536B0Bae7` [P, not called on-chain].

### Faucets

| Faucet | Gives | Limits | Gate | Evidence |
|---|---|---|---|---|
| `faucet.circle.com` | USDC, EURC, cirBTC on many testnets | One per asset and network per 2 h. 20 USDC stated. EURC amount not stated. Per-network availability not listed on page. | **reCAPTCHA**, no account | [P] |
| CDP faucet | Base Sepolia and Sepolia: ETH 0.0001 x 1000/day; USDC 1 x 10/day; EURC 1 x 10/day | Base docs separately say up to 0.1 ETH/day | CDP account or SDK; captcha not mentioned | [P] |
| Alchemy, Sepolia | 0.1 ETH / 24 h | **Needs 0.001 ETH on mainnet plus real mainnet history** | Captcha not stated | [P] |
| PoW faucet `sepolia-faucet.pk910.de` | Sepolia ETH by browser mining | Amount varies | No captcha mentioned. Online status not confirmed. | [P] |
| Google Cloud, Sepolia | Sepolia ETH | Unknown | Sign-in link present; details did not render | [U] |
| Base Sepolia others | thirdweb, QuickNode, ethfaucet (terms not stated); Alchemy (free account); Chainstack (API key) | Usually one per 24 h | Mixed | [P] |
| `faucet.gnosischain.com` | xDAI, including Chiado with `?chain=chiado`; **also mainnet** | Unknown | Page mentions **captcha** field | [P, thin] |
| Monerium sandbox | EURe via `sandbox.monerium.dev/receive` | Not stated | Sandbox login. Not an open faucet. | [P] |

Developer implications:
- Automated CI should not depend on captcha-gated faucets. Fund a persistent test wallet manually once, and run most contract interaction tests against a local fork [U].
- Sandbox EURe works only through Monerium's sandbox flow, and CI should not rely on it either.

## 13. Gaps

- Safe{Wallet} UI chain list was not directly verified, as the gateway returned 403 and the app did not render.
- Whether the Gnosis sponsored transaction scheme still works after the Gelato SDK date.
- Monerium current individual fees, limits, and whether its consumer app supports Base; whether iDEAL exists on any Monerium path.
- Coinbase EURC availability for Dutch retail users in the live product: the API shows Base and Ethereum as online, but this is the exchange API, not retail policy.
- `recover` and `burn` exact behaviour on Safes: code reading only.
- Fee measurements are a single evening's snapshot. L1 was unusually cheap; repeat over a week before quoting any costs to users.
- `mainnet.base.org` getLogs 429 may be IP-specific.
- DEX depth figures are aggregator snapshots and may miss pools.
- L2 stage data is from an undated page.

## 14. Sources

- Monerium: https://api.monerium.app/tokens, https://api.monerium.dev/tokens, https://docs.monerium.com/contracts-v2/, https://docs.monerium.com/, https://github.com/monerium/smart-contracts (`src/Token.sol`, `src/controllers/GnosisControllerToken.sol`, `src/BlacklistValidatorUpgradeable.sol`, `docs/tokendesign.md`, `docs/version2.md`), https://monerium.com/whitepapers/eure-whitepaper, https://monerium.com/blog/2026/how-bleap-combines-euro-accounts-and-onchain-finance-with-monerium/, https://safefoundation.org/blog/launching-monerium-on-safe-core-connecting-safes-to-euro-iban-accounts
- Circle: https://developers.circle.com/stablecoins/eurc-contract-addresses, https://developers.circle.com/stablecoins/usdc-contract-addresses, https://faucet.circle.com/, https://www.circle.com/legal/eurc-terms, https://www.circle.com/legal/mica-redemption-policy, https://www.circle.com/en/paymaster, https://developers.circle.com/paymaster
- ESMA: https://www.esma.europa.eu/sites/default/files/2024-12/EMTWP.csv
- Safe: https://docs.safe.global/core-api/how-to-use-api-keys, https://docs.safe.global/sdk/relay-kit, https://safe.global/blog/introducing-authenticated-api-access-and-usage-based-plans, https://help.safe.global/articles/6461820093-gas-fee-sponsorship-on-safe-transactions (snippet only), https://api.safe.global/tx-service/base/api/v1/about/
- Exchanges: https://api.exchange.coinbase.com/currencies/EURC, https://api.bitvavo.com/v2/assets, https://www.bitstamp.net/api/v2/currencies/, https://api.kraken.com/0/public/Assets, https://support.kraken.com/articles/stablecoins-supported-on-kraken, https://support.coinbase.com/customer/en/portal/articles/1767231, https://transak.com/buy/eurc, https://www.mtpelerin.com/buy-crypto
- Angle: https://www.kucoin.com/news/flash/angle-protocol-announces-phased-shutdown-of-eura-and-usda-stablecoins, https://gl.app/dao/anglegovernance.eth/proposals/0x3f5106a7716162204104979d0705b1c7ba0e7a376fd49035fd9acb81634696f7
- Chains: https://ethbeat.org/scaling/summary, https://www.theblock.co/post/365732/base-network-sequencer-failure, https://cointelegraph.com/news/gnosis-hard-fork-balancer-exploit, https://docs.polygon.technology/pos/architecture/heimdall_v2/milestones, https://www.theblock.co/amp/post/370249/polygon-hard-fork-address-finality-bug-transaction-delays
- Explorers: https://docs.etherscan.io/support/rate-limits, https://info.etherscan.com/whats-changing-in-the-free-api-tier-coverage-and-why, https://api.etherscan.io/v2/chainlist, https://docs.blockscout.com/rate-limits
- Faucets: https://docs.base.org/base-chain/tools/network-faucets, https://docs.cdp.coinbase.com/faucets/introduction/welcome, https://www.alchemy.com/faucets/ethereum-sepolia, https://sepolia-faucet.pk910.de/, https://docs.gnosischain.com/tools/Faucets
- Liquidity: https://api.dexscreener.com/latest/dex/tokens/, https://api.geckoterminal.com/api/v2/, https://api.curve.finance/v1/getPools/xdai/crypto

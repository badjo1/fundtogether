# 03. Safe and multisig integration research

Date: 2026-11-08. Nothing in the repo was changed and no transactions were sent.

Evidence tags:
- **[S]** read in primary source: `safe-smart-account` at tag v1.4.1, or the deployments JSON.
- **[L]** executed live with read-only RPC calls.
- **[M]** reasoned from source or general knowledge, not tested here. Check before relying on it.

No browser run of any JS library was done. The size and graph figures come from CDN and jspm output, read without executing it.

Scripts are in `scripts/`: `keccak.mjs`, `hashes.mjs`, `rpc.mjs`, `vector.mjs`, `sim.mjs`, `jspm.mjs`.

GitHub note: the API now gives `safe-fndn/safe-smart-account` as the download location. The `safe-global/...` raw URLs still resolve.

---

## 1. Recommendation

**Option B: direct viem calls against canonical Safe L2 1.4.1, with signatures in Postgres.**

Two additions take the useful part of C without shipping it:
1. A dev-only differential test against Protocol Kit 8.0.11, if the user permits an npm install. Golden vectors from real chain data are the fallback, and they are already available.
2. An optional Transaction Service mirror, added later behind a server-held API key. It must never be required.

Reasons:
- **Small surface.** The Safe-specific logic is small and fully specified: one EIP-712 hash, one signature encoder, four owner calls, one CREATE2 derivation. I implemented all of it in about 100 lines of dependency-free JS for this research. It matched real Safes and behaved as the source predicts in 23 scenarios against real deployed bytecode (section 13).
- **Protocol Kit is heavy here.** It costs about 4.5x the code of viem alone (1.59 MB vs 348 KB minified), 3x gzipped, plus Node polyfills. The canonical addresses and a hash function are its main contribution for this feature set.
- **Protocol Kit does not address the real risk.** Blind signing and a tampered UI are not solved by any SDK. The allowlist decoder and verification display must be written either way.
- **API Kit forces a key.** The API Kit constructor throws without an `apiKey` when it uses the hosted service (source quoted in section 2). A browser cannot hold that key, so A needs a server proxy, a paid plan decision, and an availability dependency.
- **The exit hatch is unaffected.** It comes from using canonical contracts, not from which client library is used.

**Contract version: L2 1.4.1, not 1.5.0, for now.**
- Safe{Wallet}'s source default is `LATEST_SAFE_VERSION = ... || '1.4.1'` (overridable by env, so production could differ).
- Protocol Kit's `DEFAULT_SAFE_VERSION` is also `'1.4.1'`.
- 1.4.1 lists 412 networks in the deployments JSON, 1.5.0 lists 141. Both exist on all six target chains, and the Gnosis Transaction Service lists both.
- The one real argument for 1.5.0: it uses the modern `isValidSignature(bytes32,bytes)`, so smart-wallet owners could sign off-chain (section 7). Revisit it if smart-wallet owners become a core use case.

**Use SafeL2 even if mainnet is ever added.** Its `SafeMultiSigTransaction` event lets you index executions made outside the app from logs alone, with no tracing node. [S]

---

## 2. Options compared

| | A. Protocol Kit + API Kit + Service | B. viem direct + Postgres | C. Protocol Kit + own store | D. Non-Safe |
|---|---|---|---|---|
| Version | protocol-kit 8.0.11, api-kit 5.0.4 | viem 2.57.17 | protocol-kit 8.0.11 | see below |
| jspm graph, static modules / raw bytes [L] | 214 / 2.14 MB | 116 / 505 KB (`viem/utils` alone: 76 / 358 KB) | 213 / 2.12 MB | n/a |
| Single-file esm.sh build, min / gzip [L] | 1,693,691 / 306,212, and still imports `/node/buffer.mjs` and `/node/process.mjs` | full 388,213 / 118,699; 19 exports 347,669 / 106,027 | 1,593,985 / 310,321 | n/a |
| Node polyfills in graph [L] | `buffer`, `process` via `@jspm/core` | none | `buffer`, `process` | n/a |
| CJS in graph | `safe-deployments` has only `main: dist/index.js`, no ESM entry [L] | ESM | same as A | n/a |
| Third-party service | Hard dependency | None; only an RPC | None required | Varies |
| Safe{Wallet} exit | Yes, and proposals visible there | Yes; pending proposals not visible unless mirrored or exported | Same as B | No (see D) |
| Audit | Contracts yes. No SDK audit is stated on the docs page; I found none in the package listing [L, not exhaustive] | Contracts yes. viem repo has no `audits/` directory at root [L] | Same as A | Varies |

Audit status of the contracts [S]:
- 1.4.0 was audited by Ackee (`docs/audit_1_4_0.md`). The 1.4.1 delta was a small ERC-4337 opcode-compatibility fix that was not re-audited, with the auditors notified.
- A separate `Safe_Library_Contracts_Audit_Report_1_4_1.pdf` exists.
- 1.5.0 was audited by Certora and Ackee.

### Importmap compatibility: the default pin will not work

`bin/importmap pin viem` should be expected to break. [L for the inputs, M for the outcome; I did not run it.]
- `importmap-rails` (lock 2.2.2; 2.2.3 source read) calls `api.jspm.io/generate` and `download_package_file` saves **one file per entry in `map.imports`**.
- viem has 24 entries but 116 modules, 87 of them hashed `/_/` chunks. Protocol Kit has 55 entries and 213 modules.
- viem's index imports `../_/B4681P2c.js` and similar relative paths. These are never downloaded and cannot resolve from `/assets/`.

Ways to get viem running without a runtime bundler:
1. **Preferred: one committed single-file build.** Run esbuild once at dev time (`--bundle --format=esm --minify`) over a small entry file that re-exports only what is needed, and commit it to `vendor/javascript/`. Requires user permission for a dev tool. Production has no Node.
2. **Without a dev tool:** download `https://esm.sh/viem@2.57.17/es2022/viem.bundle.mjs`, record its SHA-256, and commit it. My grep found no external absolute imports in it. This trusts esm.sh's build output once, so review it. Tree-shaking via `?exports=` saves only about 10%, so it is not worth the extra step.
3. **Not acceptable:** live CDN pins on a signing page. That hands script execution in the signing context to a third party.

Also pin with importmap's `integrity` support (present in the gem's `map.rb`). This protects against CDN or cache corruption only, not against a compromised Rails server (section 9).

### Transaction Service reliance [L]
- v6.14.0 returned `x-ratelimit-limit: 5000` with the counter decreasing per call.
- Docs: "Unauthenticated access is available for exploration only: **2 RPS** and **5,000 monthly requests**." Production needs a dashboard JWT. The docs page gives no prices or per-endpoint rules, and points to safe.global/api.
- API Kit source: "apiKey is mandatory when using api.safe.global or api.5afe.dev domains."
- Proposal endpoint in API Kit: `POST {base}/v2/safes/{safe}/multisig-transactions/`; confirmations at `/v1/multisig-transactions/{safeTxHash}/confirmations/`.
- Licensing for self-hosting: the repo LICENSE says code up to 2026-02-16 is MIT (tag `sef-mit-final`), with different terms after that. Read the rest of that file before relying on self-hosting.

### D. Alternatives: none beats Safe here
- **Coinbase Smart Wallet multi-owner: disqualified.** README: "Each owner can transact independently, without sign off from any other owner." No threshold exists, so any member could drain the group. [L]
- **Zodiac: not an alternative.** Its README defines Avatars as accounts "like Safe"; modules and modifiers sit on top of one. Enabled modules bypass owner signatures (`execTransactionFromModule`). Roles v3 lists an Oct 2026 audit. A possible later add-on (for example a Delay modifier on large withdrawals), not v1.
- **Splits: real M-of-N, wrong fit.** Docs: an "ERC-4337 v0.7 smart-contract multisig deployed as an ERC-1967 proxy", in a Root → Treasury → Operating hierarchy, where owners can upgrade the implementation. Security page claims independent audits and a bounty of up to $50,000 (auditors and dates not given on the index page I read). The cost is the exit hatch: Safe{Wallet} cannot operate these accounts, and the model is built around Splits' own workspace product. I did not evaluate its independent recovery path.

### Exit hatch, under B
- Any canonical Safe can be added by address in Safe{Wallet}. No FundTogether data is needed. [M; do this as a drill in the test plan]
- Lost if FundTogether disappears: unexecuted proposals and their collected signatures. **Funds are not at risk.** Owners just create and sign the transaction again.
- Provide a "download proposals JSON" export. Also, the `safe-wallet-monorepo` is GPL-3.0 and could be self-hosted if Safe's hosted UI also disappeared. [L for the licence]
- Queued nonce gotcha: pending proposals in our DB at nonce N conflict with anything executed at nonce N through Safe{Wallet}. The app must treat the chain as the source of truth and mark them superseded.

---

## 3. Canonical deployments [S, L]

Code hash of every address below (except plain `Safe`, whose JSON was read but not checked on-chain) matched `eth_getCode` on Gnosis 100, Base 8453, Polygon 137, Arbitrum 42161, Sepolia 11155111, Base Sepolia 84532. `VERSION()` returned 1.4.1 on all six.

| Contract (v1.4.1) | Address | codeHash |
|---|---|---|
| SafeL2 | `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762` | `0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff` |
| Safe (non-L2, do not use) | `0x41675C099F32341bf84BFc5382aF534df5C7461a` | `0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4` |
| SafeProxyFactory | `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` | `0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317` |
| MultiSendCallOnly | `0x9641d764fc13c8B624c04430C7356C1C7C8102e2` | `0xecd5bd14a08c5d2122379900b2f272bdf107a7e92423c10dd5fe3254386c9939` |
| CompatibilityFallbackHandler | `0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99` | `0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9` |
| SimulateTxAccessor | `0x3d4BA2E0884aa488718476ca2FB8Efc291A46199` | `0x91f82615581fc73b190b83d72e883608b25e392f72322035df1b13d51766cf8d` |

Do not use `MultiSend` (`0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526`). See section 6.

Note: the JSON has a separate `zksync` address set. Hard-code addresses per chain. Do not assume "canonical everywhere" if a zkSync-type chain is ever added.

---

## 4. Deployment

### setup() [S `Safe.sol:95`]
```solidity
function setup(address[] calldata _owners, uint256 _threshold, address to, bytes calldata data,
  address fallbackHandler, address paymentToken, uint256 payment, address payable paymentReceiver) external
```
Selector `0xb63e800d`.

Values to use: `to=0`, `data=0x`, `fallbackHandler=0xfd07...Ec99`, `paymentToken=0`, `payment=0`, `paymentReceiver=0`.
- A non-zero `to` means a **delegatecall during setup** (`ModuleManager.sol:38`). Refuse it: v1 has no case that needs it.
- `fallbackHandler` is what provides `isValidSignature` for a Safe acting as an owner of another Safe.
- `payment>0` pays `paymentReceiver` or `tx.origin` out of the new Safe. Refuse it.

Reverts: GS200 already set up; GS201 threshold above owner count; GS202 threshold below 1; GS203 owner is zero, sentinel, self, or adjacent duplicate; GS204 duplicate.

### Factory [S `SafeProxyFactory.sol`]
```solidity
function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce) public returns (SafeProxy proxy)  // 0x1688f0b9
event ProxyCreation(SafeProxy indexed proxy, address singleton)
// topic0 0x4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e235
```

### Address derivation [S, L]
```
salt     = keccak256( keccak256(initializer) ++ uint256(saltNonce) )
initcode = proxyCreationCode() ++ uint256(uint160(singleton))
address  = last 20 bytes of keccak256( 0xff ++ factory ++ salt ++ keccak256(initcode) )
```
`proxyCreationCode()` (`0x53e5d935`) is 486 bytes with keccak `0x1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f`, identical on Gnosis, Sepolia and Base. Fetch once and store as a constant, then assert equality in a test.

Live proof, predicted address equals the log proxy:
- Gnosis tx `0x13128f8550b5e824e4f24c80aa351e8a5ab5a67ebe29567977b03afd6a800077` → `0x5cbe483d178e62f6afa3075095984ed5391d28eb`, saltNonce 0.
- Sepolia tx `0xe664469976b9e42434eaa1f0f13671c4f55402b2de712f8afd7305885a4e3e72` → `0x9cd26fca10660d4e2b207be5693a605150eb6243`.
- A non-transacting `eth_call` to `createProxyWithNonce` also returns the predicted address. This works as a pre-flight check. [L: Gnosis, Sepolia, Base Sepolia]

### saltNonce and griefing
The initializer is inside the salt, so **nobody can front-run to the same address with different owners.** The salt needs no secrecy.

Recommended strategy:
```
saltNonce = uint256(keccak256("fundtogether.safe.v1" ++ group_uuid ++ chain_id ++ attempt))
```
Persist `saltNonce`, the exact `initializer` hex and the predicted address before asking the wallet to send. This is idempotent across retries and collision-free between groups. Avoid `saltNonce=0`: identical owner sets would collide. Owner order is part of the initializer, so canonicalise it once and store that order.

Griefing that remains:
- **Front-run with identical calldata:** the Safe is created correctly but the user's transaction reverts with `Create2 call failed`. [L, by replaying a deployed creation via `eth_call`] So on revert or on "already exists", do not show failure: run the post-deploy verification below and treat it as success.
- **Cross-chain replay:** `createProxyWithNonce` does not include chain id in the salt, so **anyone can replay the creation on any other chain, producing the same address with the original owners and threshold**. Putting chain id into the off-chain `saltNonce` only changes the number; the replay still works. [S] If member X was an initial owner and was later removed on chain A, X could deploy the original configuration on chain B. Any funds sent to that address on chain B are then exposed to the original owner set.
  - Mitigation: warn clearly about the correct chain on deposit screens.
  - `createChainSpecificProxyWithNonce` (`0xec9e80bb`) prevents replay, but makes wrong-chain deposits permanently unrecoverable. It also departs from what Protocol Kit predicts. I recommend staying with `createProxyWithNonce`. This is a judgement call the product owner should see.
- **Do not take deposits on a predicted address.** Show the deposit address only after verification.

Post-deploy verification, in the client and again on the server [S, L for the selectors]:
- `eth_getCode` non-empty, `masterCopy()` (`0xa619486e`) equals SafeL2.
- `getOwners()` and `getThreshold()` match the intent; `nonce()` is 0.
- `getModulesPaginated(0x1, 10)` is empty.
- `getStorageAt`/`eth_getStorageAt` at the guard slot `0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8` is zero.
- Fallback slot `0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5` equals the canonical handler.
- Run the same checks when importing an existing Safe. A module can move funds with no signatures; a guard can block all execution.

---

## 5. SafeTx hash and signatures

### EIP-712 [S, recomputed locally and matches both constants]
```
EIP712Domain(uint256 chainId,address verifyingContract)
  typehash 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218

SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)
  typehash 0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8
```
The domain has **no name or version**.
```
domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, chainId, safe))
structHash      = keccak256(abi.encode(SAFE_TX_TYPEHASH, to, value, keccak256(data), operation,
                                       safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce))
safeTxHash      = keccak256(0x19 ++ 0x01 ++ domainSeparator ++ structHash)
```

Live proof: local hash = event hash = `getTransactionHash` on real transactions.
| Safe (Gnosis) | Tx | Nonce | safeTxHash | Sig |
|---|---|---|---|---|
| `0x2c4b4f48aab6dadf711ea139a5c09f0295707e93` | `0xbf13e29d0b9a23148d331da17788eb2e60c4fa7828048765b27e8b3553ae10b8` | 48 | `0x88aa0a6a00dad85ba6ad66cb3910f79c22cb165a33ad285b8e874956ef67cc60` | v=32, eth_sign |
| `0xd739addd4fbee12a9157683247f28b864d8275b6` | `0x0ec9f383de546e2425e6f6f3f3020ba3c219e16cbbcc9e614dc369aec13a83dc` | 19377 | `0x6d0ab12fc076000f8e01451354e7990ac37eec4b772bb72ec3f7780302d6e5a9` | v=27, EIP-712 |

Domain separators, in the same order: `0xd03c790251cce830ea6e34ca656047dadaed855e3145373f465b64637b12b1b3` and `0xab8af25c02b5c2e414b42fd9d5632a03595b20be31a4aad79c6040c1273ce3f5`. Use all of these as golden vectors.

Client signs with `eth_signTypedData_v4`, and the `types` include `EIP712Domain: [{chainId,uint256},{verifyingContract,address}]`.

### Signature encoding [S `Safe.sol:274-334`, L]
Static part: 65 bytes per signature, concatenated in **strictly ascending numeric order of signer address**. Only the first `threshold` entries are read.

| v | Meaning | r | s | Checked as |
|---|---|---|---|---|
| 27, 28 | EIP-712 | r | s | `ecrecover(safeTxHash, v, r, s)` |
| 31, 32 | eth_sign | r | s | `ecrecover(keccak256("\x19Ethereum Signed Message:\n32" ++ safeTxHash), v-4, r, s)` |
| 0 | Contract | left-padded owner | byte offset to dynamic part, at least `threshold*65` | `isValidSignature(preimage, sig)` must return `0x20c13b0b` |
| 1 | Pre-approved | left-padded owner | ignored | `msg.sender == owner` or `approvedHashes[owner][hash] != 0` |

Rules:
- **Normalise v in the client.** Some hardware wallet paths return v=0/1, which the contract reads as contract/pre-approved. Protocol Kit's own code has a comment "Metamask with ledger returns V=0/1". Add 27 if v<27, and reject anything other than 27/28/31/32. Live result of leaving v=0: `GS022`. [L]
- **Sort by BigInt of address**, never by checksummed string.
- **Dedupe by recovered signer, not signature bytes.** The contract does not enforce low-s, so one owner can produce two valid encodings. [S]
- Contract signature dynamic part: `{32-byte length}{bytes}`, appended after the static part. Pass exactly `threshold` static entries, so offsets are simple.
- The caller can be anyone once signatures are complete. If the last signer executes, use `v=1` for them: no signature prompt, just one transaction. [L]
- Do not auto-retry an `execTransaction` made only of the sender's own `v=1` entry. In 1.4.1 that form is not hash-bound, so on a threshold-1 Safe the same calldata executes again at the next nonce. The `main` changelog documents this as a later fix. [S]

### approveHash fallback
`approveHash(bytes32)` (`0xd4d9bdcd`) must come from a current owner (GS030), emits `ApproveHash(bytes32 indexed, address indexed)`, and is **permanent with no revocation** (source comment). The only way to cancel is burning the nonce.

---

## 6. Batches and owner management

### MultiSendCallOnly [S]
`multiSend(bytes)` (`0x8d80ff0a`). Each entry is packed: `uint8 op(=0) ++ address to ++ uint256 value ++ uint256 dataLen ++ data`.

**The batch must be sent as `operation=1` (DELEGATECALL) with `to=0x9641...02e2`.** A plain call would run as the MultiSend contract, not the Safe. This is the only legal exception to the "refuse DELEGATECALL" rule, and the check must be a byte-equal address comparison.

`MultiSendCallOnly` reverts on inner op=1. Plain `MultiSend` executes inner delegatecalls, so it must be refused. A failed entry reverts the whole batch.

Use a batch only when needed. Single calls are easier to read when reviewing a signature.

### Owner calls: all `to=safe, value=0, operation=0` [S]
| Call | Selector | Notes |
|---|---|---|
| `addOwnerWithThreshold(address owner, uint256 _threshold)` | `0x0d582f13` | **Inserts at the head of the list**, so it changes the predecessor of the old head |
| `removeOwner(address prevOwner, address owner, uint256 _threshold)` | `0xf8dc5dd9` | GS201 if `ownerCount-1 < _threshold`, GS205 if prevOwner is wrong |
| `swapOwner(address prevOwner, address oldOwner, address newOwner)` | `0xe318b52b` | Keeps list position and threshold |
| `changeThreshold(uint256 _threshold)` | `0x694e80c3` | Must be between 1 and ownerCount |

`prevOwner` from `getOwners()` (`0xa0e67e2b`): for index `i`, `i==0 ? 0x0000000000000000000000000000000000000001 : owners[i-1]`. The sentinel `0x1` cannot itself be an owner (GS203).

Pitfalls:
- `prevOwner` is computed at proposal time. If another owner change executes first, the signed call can fail permanently and needs a new proposal. The UI should show this before execution. Only one owner-change proposal should be open per Safe.
- Because of `safeTxGas=0`, **the inner `GS205`/`GS201` surface as outer `GS013`.** [L] Pre-flight using simulation (section 11) to give a useful message.
- For an atomic member swap, prefer `swapOwner` over add + remove.

---

## 7. Nonces, conflicts, stale signatures, contract owners

Nonce [S]:
- `nonce` is global per Safe and strictly sequential. The on-chain value is put into the hash at execution, so a signature for any other nonce recovers a different address (`GS026`). [L]
- New proposal nonce: `max(chain nonce, highest live proposal nonce + 1)`, unless it is intentionally replacing something.
- **Inner failure semantics matter:**
  - `safeTxGas=0 && gasPrice=0` + inner failure → the whole thing reverts with `GS013`, **nonce not consumed**, proposal can be retried.
  - `safeTxGas>0` + inner failure → outer status 1, `ExecutionFailure`, **nonce consumed**, signatures dead.

Conflicts:
- Two proposals at the same nonce are allowed. The first executed wins and the other can never execute. Warn before signing when a sibling exists. Mark the loser as superseded when chain nonce > its nonce and its hash has no `ExecutionSuccess`/`ExecutionFailure`.
- **Rejection** is a normal proposal at the same nonce: `to=safe, value=0, data=0x, operation=0`, all gas fields and addresses zero. It needs `threshold` signatures. It succeeds [L] and, per the code, emits `SafeReceived(safe, 0)` [S], so deposit indexing must ignore value 0 and sender = Safe.
- This is the **only way to revoke a signature.**

Stale signatures after owner or threshold changes [L]: signatures are not bound to the owner set.
| Situation | Result |
|---|---|
| Signer removed | `GS026` |
| Threshold raised, fewer signatures | `GS020` |
| **Threshold lowered: an older partial set becomes sufficient** | Executes (returns 1) |
| Signer re-added later | Their old signature becomes valid again [M from source] |

So never store a "ready" flag. Recompute at render time from chain owners, threshold and nonce, and keep stored rows. When proposing a threshold decrease, warn that older pending proposals may become executable. Burn those nonces first, if that matters.

Contract owners [S]:
- 1.4.1 calls only the **legacy** `isValidSignature(bytes,bytes)` with the 66-byte preimage and needs `0x20c13b0b`. In the v=0 branch, `keccak256(data) == dataHash` is also required (GS027).
- **Safe as owner** works: `CompatibilityFallbackHandler` implements the legacy form. The nested Safe's owners sign `getMessageHash(preimage)` for the owning Safe (`SafeMessage(bytes message)` typehash `0x60b3cbf8...fbca`), and the result goes in the dynamic part.
- **Coinbase Smart Wallet and other bytes32-only ERC-1271 wallets:** `ERC1271.sol` defines only `isValidSignature(bytes32,bytes)`, so v=0 on 1.4.1 should fail with GS024. [M from source, not executed] 1.5.0 moved to the bytes32 form [S], and that is the upgrade reason. On 1.4.1 they use `approveHash` or execute directly with `v=1`.
- Ordinary EOAs that have added EIP-7702 code still produce recoverable ECDSA signatures. [M]

v1 suggestion: support EOAs off-chain, plus `approveHash` for any contract owner. Detect with `eth_getCode(owner)`. Add nested-Safe signing only if needed.

---

## 8. Validation rules for proposals

Client and server both apply these. On the client, a failure blocks signing.

Always required:
- `operation==0`, except exactly `to==MultiSendCallOnly` for the chain with op=1.
- `gasToken==0`, `refundReceiver==0`, `gasPrice==0`, `baseGas==0`, `safeTxGas==0`. A non-zero `gasPrice` makes the Safe pay `gasPrice*(gasUsed+baseGas)` to the receiver. [S]
- Nonce ≥ chain nonce.

`data` allowlist, applied recursively to batch entries:
| Target | Allowed |
|---|---|
| Any recipient | Empty data with value > 0 (native transfer) |
| Allowlisted token for this chain | `transfer(address,uint256)` `0xa9059cbb` with value 0 |
| The Safe itself | The four owner calls, or the empty rejection |
| Anything else | Refuse in v1 |

**Refuse self-calls in particular:** `enableModule` `0x610b5925`, `disableModule` `0xe009cfde`, `setGuard` `0xe19a9dd9`, `setFallbackHandler` `0xf08a0323`. These are plain CALLs, so a DELEGATECALL-only filter misses them, and they give permanent control or can brick the Safe. Also refuse `approve` `0x095ea7b3` and `transferFrom` `0x23b872dd`.

Safe{Wallet} remains the escape route for anything outside the allowlist.

Blind-signing protection. The Bybit incident is the reference case (NCC Group's analysis, [L]): JS injected into the Safe{Wallet} UI swapped `to`, `data`, `operation`, `value` and `safeTxGas` only at signing time, then restored the benign values for display. `operation=1` overwrote proxy slot 0, the singleton address, and funds were drained. The UI should:
- Decode locally from raw bytes and show plain language: "Send 25.00 USDC to 0xFull...ChecksumAddress on Base".
- Show full checksummed addresses, never truncated (address poisoning). Mark unknown recipients.
- Always show the raw fields: `to, value, operation, nonce, data`, plus **domain hash, message hash and safeTxHash**.
- Show "Operation: CALL". Teach users what to compare in their wallet: `to`, `value`, `data`, `operation`, and verifyingContract. [M: exact wallet displays vary; some hardware flows show only hashes, which is why the two hashes must be shown separately]
- Link to a safeTxHash verifier outside our origin (section 9).

---

## 9. Threat model: compromised Rails server

The claim "the server only stores proposals" is **not sufficient on its own, because the same server delivers the JavaScript.**

| With DB / API control only (client JS intact) | Outcome |
|---|---|
| Change `to`, `value`, `data` or nonce in JSON | Client recomputes and displays real values. If the user approves it, it's a social attack, so the display matters |
| Serve a different Safe address or owner list | Blocked if the client pins per-group address on first sight and reads owners from chain; otherwise phishing |
| Forge signatures | Impossible: `GS026` |
| Replay across Safes or chains | Impossible: the domain has chain id and Safe address |
| Censor, delete, reorder proposals; lie about status | Possible. Availability and integrity of display. Client checks status on chain. Users have the Safe{Wallet} exit |
| Create conflicting proposals at one nonce | Possible, nuisance or confusion. Warn on siblings |
| Swap RPC URL | Serious if config comes from the server. Use the wallet's provider for client reads |

| With JS delivery control | Outcome |
|---|---|
| Replace the verifier and the display | **Bybit scenario.** All client-side checks can be bypassed |
| Still can't | Sign for users, or spend without `threshold` real signatures |
| Defences that remain | Wallet's own typed-data display; hardware device; independent verification outside our origin; threshold above 1 with signers on separate devices |

Consequences:
- Client verification protects against a compromised database or API, not against compromised script delivery. SRI hashes delivered by the same server do not help. Say so plainly in security docs.
- Publish a small static verifier off the main origin (for example a repo-hosted single HTML file with the hash code inline). Input: chain, Safe, nonce, to, value, data. Output: domain, message and safe tx hashes. Third-party verifiers can also be listed once checked; I did not evaluate any.
- Publish the SHA-256 of the vendored JS for each release, and set a strict CSP: no inline, no third-party scripts, `connect-src` limited to known hosts.

### Client verification sequence
1. Receive the raw fields from the server. **Ignore any server-provided hash or decoded text**, except to compare.
2. `eth_chainId` from the wallet must equal the group's chain.
3. Via wallet provider, read `masterCopy`, `getOwners`, `getThreshold`, `nonce`.
4. Run the section 8 rules.
5. Compute the hash locally, compare to `getTransactionHash` on chain and to the server's value. Any mismatch **blocks signing** with a visible error.
6. Decode, display, sign typed data from local fields. `personal_sign`/`eth_sign` on a server-supplied hash is never used.
7. Recover the signature locally and check it is an owner before posting.
8. Before execution, verify every stored signature again and encode locally.

---

## 10. Confirming transactions

Event topics, recomputed locally [S, L for ExecutionSuccess by real logs]:
```
ExecutionSuccess(bytes32 indexed txHash, uint256 payment)   0x442e715f626346e8c54381002da614f62bee8d27386535b2521ec8540898556e
ExecutionFailure(bytes32 indexed txHash, uint256 payment)   0x23428b18acfb3ea64b08dc0c1d296ea9c09702c09083ca5272e64d115b687d23
SafeReceived(address indexed sender, uint256 value)         0x3d0ce9bfc3ed7d6862dbb28b2dea94561fe714a1b4d019aa8af39730d1ad7c3d
SafeMultiSigTransaction(...)                                0x66753cd2356569ee081232e3be8909b950e0a76c1f8460c3a5e3c2be32b11bed
SafeSetup(address indexed,address[],uint256,address,address) 0x141df868a6331af528e38c83b7aa03edc19be66e37ae67f9285bf4f8e3c6a1a8
ApproveHash(bytes32 indexed,address indexed)                0xf2a0eb156472d1440255b0d7c1e19cc07115d1051fe605b0dce69acfec884d9c
AddedOwner(address indexed)                                 0x9465fa0c962cc76958e6373a993326400c1c94f8be2fe3a952adfa7f60b2ea26
RemovedOwner(address indexed)                               0xf8d49fc529812e9a7c5c50e69c20f0dccc0db8fa95c98bc58cc9a4f1c1299eaf
ChangedThreshold(uint256)                                   0x610f7ff2b304ae8903c3de74c60c6ab1f7d6226b3f52c5161905bb5ad4039c93
EnabledModule(address indexed)                              0xecdf3a3effea5783a3c4c2140e677577666428d44ed9d474a0b3a4c9943f8440
ChangedGuard(address indexed)                               0x1151116914515bc0891ff9047a6cb32cf902546f83066499bcf8ba33d2353fa2
ChangedFallbackHandler(address indexed)                     0x5ac6c46c93c8d0e53714ba3b53db3e7c046da994313d7ed0d192028bc7c228b0
Transfer(address indexed,address indexed,uint256)           0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
```

**Safe execution.** `receipt.status==1` is **not** success.
- Require `status==1` and a log where `log.address==safe`, `topics[0]==ExecutionSuccess`, `topics[1]==expected safeTxHash`.
- `ExecutionFailure` with status 1 means the nonce was consumed and nothing happened.
- status 0 means nothing was consumed, including the GS013 case.
- Do not require `tx.to==safe`: anyone may execute, and through a contract. Search the logs.
- SafeL2 gives `SafeMultiSigTransaction` with `additionalInfo = abi.encode(nonce, sender, threshold)`, which is how to index executions made outside the app. I decoded this live.
- Poll by Safe address. Public RPCs differ: publicnode Sepolia refused address-less `eth_getLogs`, and `mainnet.base.org` returned "request limit reached". [L] Use a keyed RPC in production for indexing.

**Native deposit:** `SafeReceived` with `log.address==safe`. It's emitted from `receive()` only with empty calldata, and also for internal transfers from contracts. [S] Check confirmations and ignore zero-value entries. Forced ETH or block rewards emit nothing, so reconcile with `eth_getBalance`. [M] Senders that use a 2300-gas `.transfer` probably fail, because the proxy delegatecalls. [M]

**ERC-20 deposit:** `Transfer` with `log.address` in the **per-chain token allowlist** (any contract can emit this topic), `topics[2]==safe padded`, value in `data`. Fee-on-transfer: compare balances if such tokens are ever allowed. Wait for the chain's confirmation policy before treating deposits as final.

---

## 11. Gas, and server verification without a key

### Gas [S `Safe.sol:197-212`, L]
Use `safeTxGas=0, baseGas=0, gasPrice=0, gasToken=0, refundReceiver=0`. This is also compatible with Safe{Wallet}, and it was seen on both real vectors.

| Setting | Behaviour | Live result |
|---|---|---|
| `safeTxGas=0, gasPrice=0` | Inner call gets all gas less 2500; inner failure reverts everything with GS013; gas estimation is reliable | `GS013` |
| `safeTxGas=50000, gasPrice=0` | Acts as a minimum; inner failure caught; **returns false, nonce burned**; wallet estimate can be too low | ret 0 |
| Gas limit too low for `safeTxGas` (86,016 limit) | `GS010` | `GS010` |
| `gasPrice>0` | Refund to `refundReceiver` or `tx.origin` from Safe funds. Refuse | not run |

Pitfalls:
- `eth_estimateGas` needs a fully valid signature set or it reverts. So it works only at execution time. Add a buffer of 20-30% (judgement), since a limit that is too low gives only a retryable GS013.
- Before signatures exist, use `simulateAndRevert(accessor, simulate(to,value,data,op))` via `eth_call`.
  - Selectors: `0xb4faba09` and `0x1c5fb211`. Accessor: `0x3d4B...9`.
  - It always "reverts"; read the revert data as `success | len | estimate | innerSuccess | offset | returnLen | returnData`.
  - Live, a zero-value self-call returned `1, 0x80, 0x8f6 (2294 gas), 1, 0x60, 0`. Some RPC client libraries hide revert data, so test that path.
- Executor pays gas in native token. No Safe refund is used. Members need gas funds on the chain, which is a product issue. On L2s the fee includes an L1 data part that wallets normally handle. [M]

### Server reads via `eth_call`
| Purpose | Call |
|---|---|
| Owners | `getOwners()` `0xa0e67e2b` |
| Threshold | `getThreshold()` `0xe75235b8` |
| Nonce | `nonce()` `0xaffed0e0` |
| Hash | `getTransactionHash(...)` `0xd8d11f78` |
| Whole set | `checkSignatures(bytes32,bytes,bytes)` `0x934f3a11` |
| One signature | `checkNSignatures(bytes32,bytes,bytes,uint256)` `0x12fb68e0` with n=1 |
| Domain | `domainSeparator()` `0xf698da25` |
| Recover | `eth_call` to `0x0000000000000000000000000000000000000001` with `hash ++ pad32(v) ++ r ++ s` |

All verified live, except `checkNSignatures` from source only.
- `checkSignatures` returned empty on success and **`GS026` on a one-bit tampered signature**. [L]
- Args: `dataHash`, 66-byte preimage (`0x1901 ++ domain ++ struct`), signatures.
- For `v=1`, `eth_call` trusts the `from` field, so **always call with `from=0x0`**, or anyone can claim approval.
- Server checks are advisory, for spam and UX. They trust the RPC. The contract is the final authority.

### Ruby: keccak and recover [L for metadata; none installed]
| Option | Native build | Notes |
|---|---|---|
| Precompile `0x01` plus `eth_call` | None | No new crypto dependency; needs RPC; verified live, matched owners |
| `keccak` 1.3.3 | C ext, compiled at install (`platform: ruby`) | No runtime deps; the Dockerfile build stage has `build-essential`. **Fits best.** |
| `eth` (eth.rb) 0.5.18 | `rbsecp256k1`, `keccak`, `scrypt` and more | Deps: `bls12-381, httpx, konstructor, openssl, scrypt, ...`. rbsecp256k1 README lists `automake`, `libtool` etc. for its bundled libsecp256k1; the Dockerfile has neither, and its build pulls via `mini_portile2`. ABI encoding is the real benefit |
| `rbsecp256k1` 6.0.2 alone | Same as above | Fast, but overkill here |
| `ecdsa` 1.2.0 | Pure Ruby | Has `recover_public_key`; last release 2014 |
| `digest-sha3` 1.1.0 | C ext | Last release 2015. Avoid |
| `digest-keccak` 0.0.7 | Not checked | Small usage (92k downloads) |
| `sha3` 2.2.4 | C ext | README presents FIPS 202. **SHA3-256 is not Keccak-256.** Do not confuse them |
| Ruby OpenSSL | None | `OpenSSL::Digest.new("KECCAK-256")` **failed** locally on OpenSSL 3.5.9: "unknown object name" |

**Recommendation:** `keccak` + precompile via `eth_call` + a small hand-written ABI helper for the fixed shapes. Move to `eth` only if other team needs (SIWE, wider ABI use) justify changing the Dockerfile. Coordinate with whoever covers wallet auth.

---

## 12. ABI fragments required

```js
// SafeProxyFactory
"function createProxyWithNonce(address _singleton, bytes initializer, uint256 saltNonce) returns (address proxy)"
"function proxyCreationCode() pure returns (bytes)"
"event ProxyCreation(address indexed proxy, address singleton)"

// Safe
"function setup(address[] _owners, uint256 _threshold, address to, bytes data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)"
"function execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes signatures) payable returns (bool success)"  // 0x6a761202
"function getTransactionHash(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, uint256 _nonce) view returns (bytes32)"
"function checkSignatures(bytes32 dataHash, bytes data, bytes signatures) view"
"function checkNSignatures(bytes32 dataHash, bytes data, bytes signatures, uint256 requiredSignatures) view"
"function approveHash(bytes32 hashToApprove)"
"function approvedHashes(address, bytes32) view returns (uint256)"  // 0x7d832974
"function getOwners() view returns (address[])"
"function getThreshold() view returns (uint256)"
"function isOwner(address owner) view returns (bool)"  // 0x2f54bf6e
"function nonce() view returns (uint256)"
"function domainSeparator() view returns (bytes32)"
"function VERSION() view returns (string)"  // 0xffa1ad74
"function masterCopy() view returns (address)"  // handled by the proxy
"function getModulesPaginated(address start, uint256 pageSize) view returns (address[] array, address next)"  // 0xcc2f8452
"function getStorageAt(uint256 offset, uint256 length) view returns (bytes)"  // 0x5624b25b
"function simulateAndRevert(address targetContract, bytes calldataPayload)"
"function addOwnerWithThreshold(address owner, uint256 _threshold)"
"function removeOwner(address prevOwner, address owner, uint256 _threshold)"
"function swapOwner(address prevOwner, address oldOwner, address newOwner)"
"function changeThreshold(uint256 _threshold)"
// plus the events in section 10

// MultiSendCallOnly
"function multiSend(bytes transactions) payable"
// SimulateTxAccessor
"function simulate(address to, uint256 value, bytes data, uint8 operation) returns (uint256 estimate, bool success, bytes returnData)"
// ERC-20
"function transfer(address to, uint256 amount) returns (bool)"
"function balanceOf(address) view returns (uint256)"
"function decimals() view returns (uint8)"
```
All listed selectors were recomputed locally with a keccak implementation checked against `keccak("")` and the contract's typehash constants.

Revert codes to translate in the UI: GS010 too little gas; GS013 inner call failed; GS020 too few signatures; GS021-23 bad contract signature offset; GS024 invalid contract signature; GS025 hash not approved; GS026 wrong signer, order, nonce or hash; GS027 preimage mismatch; GS030 only owners can approve.

---

## 13. Test plan

### Layer 1: pure unit tests (no network)
Ruby and JS use the same JSON fixture file.
- Keccak, typehashes, selectors, topics (section 5, section 10 values).
- safeTxHash and domain from the two golden transactions.
- CREATE2 from the two deployment transactions.
- Signature encoding: sort order, v normalisation, contract signature offset, the worked example in `docs/signatures.md`.
- Allowlist: each refused case in section 8, DELEGATECALL exception by exact address, nested batch entries, non-zero gas fields.
- prevOwner calculation including head and after an add.

### Layer 2: real data via read-only RPC (no local tools)
`vector.mjs` shows this approach. Run nightly, not per commit, because public RPC is rate-limited.
- Code hash of canonical contracts on all six chains.
- Fixture recheck: local hash = event hash = `getTransactionHash`.
- `checkSignatures` passes on real signatures and reverts on tampered ones. Owner sets can change over time, so pin a fixture block with an archive RPC or use your own testnet Safe.

### Layer 3: real bytecode via `eth_call` + state override (no local tools, no funds)
`sim.mjs` is a working version: it plants the real proxy runtime and an owner list at a random address, then signs with throwaway keys. Storage slots from `SafeStorage.sol`: singleton 0, modules 1, owners 2, ownerCount 3, threshold 4, nonce 5.

Results on the Gnosis public RPC. The first scenarios were repeated on Sepolia with the same results. On Base Sepolia only the `createProxyWithNonce` simulation was run.

| Scenario | Result |
|---|---|
| 2-of-3 EIP-712, ascending | ret 1 |
| Descending; duplicate signer | GS026 |
| One signature | GS020 |
| v=0 unnormalised | GS022 |
| eth_sign with v+4 | ret 1 |
| eth_sign without v+4 | GS026 |
| v=1, sender is owner | ret 1 |
| v=1, other sender, not approved | GS025 |
| Signer no longer owner | GS026 |
| Threshold raised / lowered | GS020 / ret 1 |
| Wrong nonce | GS026 |
| Rejection self-call | ret 1 |
| Inner revert, `safeTxGas=0` | GS013 |
| Inner revert, `safeTxGas=50000` | ret 0 |
| Gas limit too low for safeTxGas | GS010 |
| `changeThreshold(3)` / `(4)` with 3 owners | ret 1 / GS013 |
| `removeOwner` head with sentinel; middle with predecessor | ret 1 |
| `removeOwner` wrong predecessor | GS013 |

**Limits:** `eth_call` returns no logs and persists nothing, so a sequence of transactions, events and receipts cannot be tested this way. State override support differs by RPC. `eth_simulateV1` may return logs where supported. [M, untested]

### Layer 4: live testnet, manual and scripted
Needs user-held throwaway wallets and testnet funds. **I sent nothing.** Sepolia and Base Sepolia:
- Deploy 2-of-3, verify, deposit native and a test ERC-20.
- Propose, sign, execute, check `ExecutionSuccess`.
- Add, remove, swap owner; change threshold; conflict and rejection.
- Force a GS013 retry; execution by a non-owner.
- `approveHash` with a contract owner; a Ledger or similar if one is available, to check v handling.
- **Exit drill:** open the Safe in Safe{Wallet} with FundTogether stopped, and execute a transfer.
- **Tamper drill:** alter stored proposal rows and confirm the client blocks signing.

### Layer 5: if the user permits a local fork (for example Foundry's `anvil --fork-url`)
Adds what layers 1-4 cannot provide:
- Real multi-transaction sequences with state carried over, real receipts and logs.
- `ExecutionFailure` log parsing and SafeReceived/Transfer indexers against real receipts.
- Account impersonation and ERC-20 balance setting without funds; nested Safe owners; approveHash flows.
- Deterministic CI with no rate limits; forced reorg scenarios for confirmations logic.
- Fast differential tests against Protocol Kit, if installed.

It does not test wallets in a browser. System tests would need an injected mock EIP-1193 provider backed by the fork.

---

## 14. Decisions the team or user must make

1. Vendoring method: esbuild once at dev time (needs permission) or a checksummed esm.sh file.
2. `createProxyWithNonce` vs chain-specific (recommend the former; section 4 trade-off).
3. Contract owners in v1: `approveHash` only (recommended), or nested signing too.
4. Mirror to the Transaction Service: not in v1. Needs a key held by the server and a plan price I could not read from the docs page.
5. Whether the `keccak` gem is acceptable, or `eth` is wanted for other work.
6. Whether a local fork tool may be installed.

## 15. Not verified

- No library was run in a browser, and `bin/importmap pin` was not run. That failure is read from source.
- Safe{Wallet} production behaviour (default version in the hosted build, adding an arbitrary Safe) is from source and general knowledge. The exit drill covers it.
- Coinbase Smart Wallet failing v=0 on 1.4.1 is inferred from source, not executed.
- `approveHash` and contract signature paths were not simulated end to end; only source reading.
- Splits' independent recovery path and audit details were not checked in depth.
- Hardware wallet display behaviour is not tested.

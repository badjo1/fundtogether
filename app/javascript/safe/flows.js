// The user-facing flows. Controllers call these and only translate steps to events.
// Rule throughout: nothing returns as a success until the chain or the server has confirmed it.
import { createReader, createRpcProvider } from "safe/reader"
import { WalletError, refuse } from "wallet/errors"
import { encodeFunctionData, getAddress } from "viem"
import { ERC20_ABI, FACTORY_ABI, SAFE_ABI } from "safe/abi"
import { formatAmount, parseAmount } from "safe/amounts"
import { FALLBACK_HANDLER, SAFE_L2_SINGLETON, SAFE_PROXY_FACTORY, ZERO_ADDRESS } from "safe/constants"
import { verifyDeployedSafe, verifyDeployment } from "safe/deploy"
import { preflightGas } from "safe/gas"
import { typedDataPayload } from "safe/hash"
import { assertThresholdRules } from "safe/policy"
import { interpretExecution, interpretTransfer, proxyCreatedAt, receiptSucceeded, waitForReceipt } from "safe/receipts"
import { encodeSignatures, normalizeSignature, recoverSigner } from "safe/signatures"
import { parseAddress } from "safe/values"
import { localProposalHash, verifyProposal } from "safe/verify"

const noop = () => {}

// The wallet when it is connected and on the right chain, otherwise the page's RPC.
export function readerFor(session, chain) {
  const snapshot = session.snapshot()
  if (snapshot.state === "connected" && snapshot.chainId === chain.chainId && session.provider) {
    return createReader(session.provider)
  }
  if (chain.rpcUrls.length === 0) throw new WalletError("chain_read_failed", { details: { reason: "no rpc" } })
  return createReader(createRpcProvider(chain.rpcUrls))
}

// Best effort: a failed hint must not hide an on-chain result from the user.
async function sendHint(work, onHintFailed) {
  try {
    return await work()
  } catch (error) {
    onHintFailed(error)
    return null
  }
}

async function sendTransaction({ session, from, chainId, to, data, gas, onLate }) {
  return session.request("eth_sendTransaction", [{ from, to, data, value: "0x0", gas }], {
    expected: { address: from, chainId },
    onLate
  })
}

// --- Deployment

export async function deploySafe({ session, http, urls, chain, intent = null, acknowledgeRisk = false, createParams = null, onStep = noop, receiptOptions, onHintFailed = noop }) {
  onStep("preparing")
  const deployment = await loadDeployment(http, urls, createParams)
  const verified = verifyDeployment(deployment, { chainId: chain.chainId, intent })
  assertThresholdRules({ ownerCount: verified.owners.length, threshold: verified.threshold, acknowledged: acknowledgeRisk || deployment.status === "active" })

  const { address: from } = await session.assertLive({ chainId: chain.chainId })
  const reader = createReader(session.provider)
  await reader.assertChain(chain.chainId)
  const finish = async (txHash) => {
    onStep("verifying_deployment")
    await verifyDeployedSafe(reader, verified)
    return { safeAddress: verified.safeAddress, txHash, deployment }
  }

  // PATCH makes the server verify too. Without a hash it just checks the address.
  const askServerToVerify = (hash) => sendHint(() => http.patch(urls.safe, hash ? { deploy_tx_hash: hash } : {}), onHintFailed)

  // Already there, deployed by us earlier or by a front-runner with identical calldata.
  if (await reader.hasCode(verified.safeAddress)) {
    const result = await finish(deployment.deploy_tx_hash || null)
    await askServerToVerify(deployment.deploy_tx_hash || null)
    return result
  }

  // A previous attempt may still be on its way. Do not send a second one.
  let txHash = await resumableHash(reader, deployment.deploy_tx_hash)

  if (!txHash) {
    onStep("verifying")
    const simulated = await reader.call(SAFE_PROXY_FACTORY, FACTORY_ABI, "createProxyWithNonce", [
      deployment.singleton, verified.initializer, verified.saltNonce
    ], { from })
    if (simulated.toLowerCase() !== verified.safeAddress) throw refuse("address_mismatch", { simulated })

    onStep("checking_gas")
    const gas = await preflightGas(reader, { from, to: SAFE_PROXY_FACTORY, data: verified.data, chain })

    onStep("confirm_in_wallet")
    txHash = await sendTransaction({ session, from, chainId: chain.chainId, to: SAFE_PROXY_FACTORY, data: verified.data, gas, onLate: askServerToVerify })

    onStep("saving", { txHash })
    await askServerToVerify(txHash)
  }

  onStep("waiting_receipt", { txHash })
  const receipt = await waitForReceipt(reader, txHash, receiptOptions)

  // "Create2 call failed" can mean someone deployed the identical Safe first: check before failing.
  const created = proxyCreatedAt(receipt, { factory: SAFE_PROXY_FACTORY, proxy: verified.safeAddress })
  if (!created && !await reader.hasCode(verified.safeAddress)) throw new WalletError("deploy_failed", { details: { txHash } })

  const result = await finish(txHash)
  await askServerToVerify(txHash)
  return result
}

// The configuration locks once deploying, so a retry after a reload reads what is there.
async function loadDeployment(http, urls, createParams) {
  if (!createParams) return http.get(urls.safe)
  try {
    return await http.post(urls.safe, createParams)
  } catch (error) {
    if (error.details?.error === "safe_locked") return http.get(urls.safe)
    throw error
  }
}

// A stored hash is only a hint: it counts if the chain knows it and it has no failed receipt.
async function resumableHash(reader, hash) {
  if (!hash) return null
  const transaction = await reader.transaction(hash)
  if (!transaction) return null
  const receipt = await reader.receipt(hash)
  return receipt && !receiptSucceeded(receipt) ? null : hash
}

// --- Proposals: review, sign

export async function reviewProposal({ session, http, urls, chain, safeAddress, onStep = noop }) {
  onStep("loading")
  const proposal = await http.get(urls.proposal)
  onStep("verifying")
  const verified = await verifyProposal({ proposal, reader: readerFor(session, chain), chain, safeAddress })
  return { proposal, verified, display: verified.display }
}

// Re-fetches and re-verifies at signing time. `reviewedHash` is the hash the user saw; if anything
// moved since the review, the user has to look again.
export async function signProposal({ session, http, urls, chain, safeAddress, linked = [], reviewedHash, onStep = noop }) {
  const safe = parseAddress(safeAddress)
  const { address: signer } = await session.assertLive({ chainId: chain.chainId })
  if (!linked.map((entry) => entry.toLowerCase()).includes(signer)) throw new WalletError("address_not_linked")

  onStep("loading")
  const proposal = await http.get(urls.proposal)
  onStep("verifying")
  const verified = await verifyProposal({ proposal, reader: createReader(session.provider), chain, safeAddress: safe })
  if (reviewedHash && verified.hash !== reviewedHash.toLowerCase()) {
    throw refuse("review_outdated", { reviewed: reviewedHash, current: verified.hash })
  }
  if (!verified.owners.includes(signer)) throw refuse("not_owner", { signer })
  if (verified.valid.some((entry) => entry.signer === signer)) throw new WalletError("already_signed")

  onStep("sign_typed_data", { display: verified.display })
  const raw = await session.request("eth_signTypedData_v4", [signer, typedDataPayload({ chainId: chain.chainId, safe, tx: verified.tx })], {
    expected: { address: signer, chainId: chain.chainId },
    keepSubmitting: true
  })

  // Inside submit, so a refused signature also leaves the session state clean.
  return session.submit(async () => {
    const signature = normalizeSignature(raw)
    if (await recoverSigner(verified.hash, signature) !== signer) throw refuse("signature_mismatch")

    onStep("saving_signature")
    const updated = await http.post(urls.signatures, { signature })
    return { proposal: updated, signature, signer, display: verified.display }
  })
}

// --- Proposals: execute

function outcomeResult({ outcome, txHash, hash }) {
  switch (outcome) {
    case "success":
      return { outcome, txHash, safeTxHash: hash }
    case "failure":
      throw new WalletError("execution_failed", { details: { txHash } })
    case "reverted":
      throw new WalletError("execution_reverted", { details: { txHash } })
    default:
      throw new WalletError("execution_unconfirmed", { details: { txHash } })
  }
}

// Live signature count against live owners, threshold and nonce. Never a stored "ready" flag.
export async function executionReadiness({ session, http, urls, chain, safeAddress, onStep = noop }) {
  const { verified, display, proposal } = await reviewProposal({ session, http, urls, chain, safeAddress, onStep })
  const sufficient = await fundCanPay(readerFor(session, chain), proposal, verified)
  return {
    proposal,
    display,
    sufficient,
    ready: verified.valid.length >= Number(verified.threshold) && verified.tx.nonce === verified.chainNonce && sufficient,
    isNext: verified.tx.nonce === verified.chainNonce,
    have: verified.valid.length,
    need: Number(verified.threshold)
  }
}

// Live, like everything else here. Never the server's word for it.
async function fundCanPay(reader, proposal, verified) {
  if (proposal.kind === "transfer_token") return await reader.tokenBalance(verified.tx.to, verified.safe) >= BigInt(proposal.params.amount)
  if (proposal.kind === "transfer_native") return await reader.nativeBalance(verified.safe) >= verified.tx.value
  return true
}

export async function executeProposal({ session, http, urls, chain, safeAddress, onStep = noop, receiptOptions, onHintFailed = noop }) {
  const safe = parseAddress(safeAddress)
  const { address: from } = await session.assertLive({ chainId: chain.chainId })
  const reader = createReader(session.provider)

  onStep("loading")
  const proposal = await http.get(urls.proposal)

  // A hash from an earlier attempt: follow that instead of sending again.
  const earlier = await resumableHash(reader, proposal.execution_tx_hash)
  if (earlier) {
    const hash = localProposalHash({ proposal, chain, safe })
    onStep("waiting_receipt", { txHash: earlier })
    return finishExecution({ reader, http, urls, safe, hash, txHash: earlier, receiptOptions, onHintFailed })
  }

  onStep("verifying")
  const verified = await verifyProposal({ proposal, reader, chain, safeAddress: safe })
  if (verified.tx.nonce !== verified.chainNonce) throw refuse("nonce_not_current", { nonce: verified.tx.nonce.toString(), chainNonce: verified.chainNonce.toString() })

  if (!await fundCanPay(reader, proposal, verified)) throw new WalletError("insufficient_fund_balance", { refusal: true })

  const signatures = encodeSignatures(verified.valid, verified.threshold)
  const { tx } = verified
  const data = encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "execTransaction",
    args: [tx.to, tx.value, tx.data, tx.operation, tx.safeTxGas, tx.baseGas, tx.gasPrice, tx.gasToken, tx.refundReceiver, signatures]
  })

  onStep("checking_gas")
  const gas = await preflightGas(reader, { from, to: safe, data, chain })

  onStep("confirm_in_wallet")
  const onLate = (late) => sendHint(() => http.post(urls.execution, { tx_hash: late }), onHintFailed)
  const txHash = await sendTransaction({ session, from, chainId: chain.chainId, to: safe, data, gas, onLate })

  // Only a hint for the server's sync. The state changes when the chain says so.
  onStep("saving", { txHash })
  await sendHint(() => http.post(urls.execution, { tx_hash: txHash }), onHintFailed)

  onStep("waiting_receipt", { txHash })
  return finishExecution({ reader, http, urls, safe, hash: verified.hash, txHash, receiptOptions, onHintFailed })
}

async function finishExecution({ reader, http, urls, safe, hash, txHash, receiptOptions, onHintFailed }) {
  const receipt = await waitForReceipt(reader, txHash, receiptOptions)
  const outcome = interpretExecution(receipt, { safe, safeTxHash: hash })
  // Mined now: this one reads the receipt on the server before the page reloads. The earlier hint found it
  // pending, and the background sync can lose the race, so the page would still say the proposal is open.
  await sendHint(() => http.post(urls.execution, { tx_hash: txHash }), onHintFailed)
  await sendHint(() => http.post(urls.sync, { tx_hash: txHash }), onHintFailed)
  return outcomeResult({ outcome, txHash, hash })
}

// --- Contribution

export async function readBalances({ session, chain, tokenAddress, safeAddress }) {
  const token = allowedToken(chain, tokenAddress)
  const safe = parseAddress(safeAddress)
  const reader = readerFor(session, chain)
  await reader.assertChain(chain.chainId)
  const address = session.snapshot().state === "connected" ? session.snapshot().address : null
  const [fund, wallet, gas] = await Promise.all([
    reader.tokenBalance(token.address, safe),
    address ? reader.tokenBalance(token.address, address) : null,
    address ? reader.nativeBalance(address) : null
  ])
  const pack = (units, decimals, symbol) => units === null ? null : { units: units.toString(), formatted: formatAmount(units, decimals), symbol }
  return {
    fund: pack(fund, token.decimals, token.symbol),
    wallet: pack(wallet, token.decimals, token.symbol),
    gas: pack(gas, chain.nativeCurrency.decimals, chain.nativeCurrency.symbol)
  }
}

function allowedToken(chain, tokenAddress) {
  const address = parseAddress(tokenAddress)
  const token = chain.tokens.find((entry) => entry.address === address)
  if (!token) throw refuse("token_not_allowed", { address })
  return token
}

// What a browser can check about where money goes, without believing the server: a real Safe proxy of the canonical
// contract, with nothing bolted on, at an address that follows from the deployment data. Not checkable here: whether
// these are the right people. So the owners read from the chain go on the screen, to be recognised.
export async function verifyFundSafe({ reader, chain, safeAddress, deployment = null }) {
  const safe = parseAddress(safeAddress)
  if (!await reader.hasCode(safe)) throw refuse("safe_not_deployed")
  if (await reader.singleton(safe) !== SAFE_L2_SINGLETON) throw refuse("safe_not_canonical")
  if (await reader.guard(safe) !== ZERO_ADDRESS) throw refuse("safe_has_guard")
  if (await reader.fallbackHandler(safe) !== FALLBACK_HANDLER) throw refuse("safe_bad_fallback")
  if ((await reader.modules(safe)).length > 0) throw refuse("safe_has_modules")
  if (deployment) {
    const derived = verifyDeployment(deployment, { chainId: chain.chainId })
    if (derived.safeAddress !== safe) throw refuse("address_mismatch", { expected: safe, derived: derived.safeAddress })
  }
  const [owners, threshold] = await Promise.all([reader.owners(safe), reader.threshold(safe)])
  return { address: getAddress(safe), owners: owners.map((owner) => getAddress(owner)), threshold: threshold.toString() }
}

export async function checkDestination({ session, http, urls, chain, safeAddress }) {
  const reader = readerFor(session, chain)
  await reader.assertChain(chain.chainId)
  const deployment = urls?.safe ? await http.get(urls.safe) : null
  return verifyFundSafe({ reader, chain, safeAddress, deployment })
}

export async function contribute({ session, http, urls, chain, tokenAddress, safeAddress, amount, onStep = noop, receiptOptions, onHintFailed = noop }) {
  const token = allowedToken(chain, tokenAddress)
  const safe = parseAddress(safeAddress)
  if (safe === ZERO_ADDRESS) throw refuse("recipient_forbidden")
  const units = parseAmount(amount, token.decimals)

  const { address: from } = await session.assertLive({ chainId: chain.chainId })
  const reader = createReader(session.provider)
  await reader.assertChain(chain.chainId)

  onStep("checking_balance")
  const deployment = urls.safe ? await http.get(urls.safe) : null
  await verifyFundSafe({ reader, chain, safeAddress: safe, deployment })
  const decimals = await reader.tokenDecimals(token.address)
  if (decimals !== token.decimals) throw refuse("token_mismatch", { decimals })
  const balance = await reader.tokenBalance(token.address, from)
  if (balance < units) throw new WalletError("insufficient_token", { details: { balance: balance.toString(), units: units.toString() } })

  const data = encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [safe, units] })

  onStep("checking_gas")
  const gas = await preflightGas(reader, { from, to: token.address, data, chain })

  onStep("confirm_in_wallet")
  const onLate = (late) => sendHint(() => http.post(urls.sync, { tx_hash: late }), onHintFailed)
  const txHash = await sendTransaction({ session, from, chainId: chain.chainId, to: token.address, data, gas, onLate })

  onStep("waiting_receipt", { txHash })
  const receipt = await waitForReceipt(reader, txHash, receiptOptions)
  const outcome = interpretTransfer(receipt, { token: token.address, from, to: safe, amount: units })
  await sendHint(() => http.post(urls.sync, { tx_hash: txHash }), onHintFailed)

  if (outcome === "reverted") throw new WalletError("transfer_reverted", { details: { txHash } })
  if (outcome !== "success") throw new WalletError("transfer_unconfirmed", { details: { txHash } })
  return {
    txHash,
    units: units.toString(),
    formatted: formatAmount(units, token.decimals),
    symbol: token.symbol
  }
}

// Steps 1 to 5 of the signing flow in docs/ARCHITECTURE.md. Everything here is computed locally or
// read from the chain. Server values are only ever compared against, and any difference refuses.
import { getAddress } from "viem"
import { refuse } from "wallet/errors"
import { formatAmount } from "safe/amounts"
import { buildAction } from "safe/calldata"
import { SAFE_L2_SINGLETON, ZERO_ADDRESS } from "safe/constants"
import { domainHash, messageHash, safeTxHash } from "safe/hash"
import { assertPolicy } from "safe/policy"
import { validSignatures } from "safe/signatures"
import { cleanText, parseAddress, parseBytes32, parseUintString } from "safe/values"

const CLOSED_STATES = new Set(["executed", "failed", "superseded", "rejected", "cancelled", "canceled"])

// Only call after assertPolicy has passed on the same fields.
function parseFields(proposal) {
  return {
    to: proposal.to,
    value: BigInt(proposal.value),
    data: proposal.data,
    operation: 0,
    safeTxGas: 0n,
    baseGas: 0n,
    gasPrice: 0n,
    gasToken: ZERO_ADDRESS,
    refundReceiver: ZERO_ADDRESS,
    nonce: BigInt(proposal.nonce)
  }
}

// The allowed token comes from the page's chain config (config/chains.yml), not from the proposal.
function resolveToken(proposal, chain) {
  if (!proposal.token) return chain.tokens[0] || null
  const address = parseAddress(proposal.token.address)
  const allowed = chain.tokens.find((token) => token.address === address)
  if (!allowed) throw refuse("token_not_allowed", { address })
  return allowed
}

function describe({ proposal, tx, token, chain }) {
  const params = proposal.params || {}
  const checksum = (address) => (address ? getAddress(address) : null)
  const base = { kind: proposal.kind, title: cleanText(proposal.title) }

  switch (proposal.kind) {
    case "transfer_token": {
      const amount = formatAmount(parseUintString(params.amount), token.decimals)
      return { ...base, recipient: checksum(params.recipient), amount, symbol: token.symbol, summary: `Stuur ${amount} ${token.symbol} naar ${checksum(params.recipient)}` }
    }
    case "transfer_native": {
      const { symbol, decimals } = chain.nativeCurrency
      const amount = formatAmount(tx.value, decimals)
      return { ...base, recipient: checksum(params.recipient), amount, symbol, summary: `Stuur ${amount} ${symbol} naar ${checksum(params.recipient)}` }
    }
    case "add_owner":
      return { ...base, owner: checksum(params.owner), summary: `Voeg eigenaar ${checksum(params.owner)} toe, met ${params.threshold} handtekening(en) nodig` }
    case "remove_owner":
      return { ...base, owner: checksum(params.owner), summary: `Verwijder eigenaar ${checksum(params.owner)}, met ${params.threshold} handtekening(en) nodig` }
    case "swap_owner":
      return { ...base, owner: checksum(params.new_owner), summary: `Vervang eigenaar ${checksum(params.old_owner)} door ${checksum(params.new_owner)}` }
    case "change_threshold":
      return { ...base, summary: `Wijzig het aantal benodigde handtekeningen naar ${params.threshold}` }
    case "rejection":
      return { ...base, summary: `Wijs het voorstel met nonce ${tx.nonce} af` }
    default:
      throw refuse("unknown_kind", { kind: proposal.kind })
  }
}

// For following an earlier execution, when the nonce has moved on and live checks no longer apply.
// The event is matched against this local hash, so a server cannot claim another tx as this proposal's.
export function localProposalHash({ proposal, chain, safe }) {
  if (Number(proposal.chain_id) !== chain.chainId) throw refuse("proposal_chain_mismatch")
  if (parseAddress(proposal.safe_address) !== safe) throw refuse("proposal_safe_mismatch")
  assertPolicy(proposal, { safe, token: resolveToken(proposal, chain)?.address ?? null })
  const hash = safeTxHash({ chainId: chain.chainId, safe, tx: parseFields(proposal) })
  if (hash !== parseBytes32(proposal.safe_tx_hash)) throw refuse("hash_mismatch", { local: hash, server: proposal.safe_tx_hash })
  return hash
}

export async function verifyProposal({ proposal, reader, chain, safeAddress }) {
  if (!proposal || typeof proposal !== "object") throw refuse("proposal_malformed")

  const safe = parseAddress(safeAddress)
  if (Number(proposal.chain_id) !== chain.chainId) throw refuse("proposal_chain_mismatch")
  if (parseAddress(proposal.safe_address) !== safe) throw refuse("proposal_safe_mismatch")
  if (CLOSED_STATES.has(proposal.state)) throw refuse("proposal_closed", { state: proposal.state })
  const serverHash = parseBytes32(proposal.safe_tx_hash)

  const token = resolveToken(proposal, chain)

  // Step 3 comes first in code because step 2 needs live owners for prevOwner.
  await reader.assertChain(chain.chainId)
  if (await reader.singleton(safe) !== SAFE_L2_SINGLETON) throw refuse("safe_not_canonical")
  const [owners, threshold, chainNonce] = await Promise.all([reader.owners(safe), reader.threshold(safe), reader.nonce(safe)])

  assertPolicy(proposal, { safe, token: token?.address ?? null, currentNonce: chainNonce })
  const tx = parseFields(proposal)

  if (token && proposal.kind === "transfer_token") {
    const decimals = await reader.tokenDecimals(token.address)
    if (decimals !== token.decimals || Number(proposal.token?.decimals) !== decimals) {
      throw refuse("token_mismatch", { decimals, claimed: proposal.token?.decimals })
    }
  }

  // Step 2: rebuild and compare.
  const rebuilt = buildAction(
    { kind: proposal.kind, params: proposal.params, nonce: tx.nonce },
    { safe, token: token?.address ?? null, owners, threshold, currentNonce: chainNonce }
  )
  if (rebuilt.to !== tx.to || rebuilt.value !== tx.value || rebuilt.data.toLowerCase() !== tx.data) {
    throw refuse("calldata_mismatch", { expected: rebuilt.data, server: tx.data })
  }

  // Step 4: local hash against the server's and the Safe's own.
  const localHash = safeTxHash({ chainId: chain.chainId, safe, tx })
  if (localHash !== serverHash) throw refuse("hash_mismatch", { local: localHash, server: serverHash })
  const onChainHash = await reader.onChainTransactionHash(safe, tx)
  if (onChainHash.toLowerCase() !== localHash) throw refuse("chain_hash_mismatch", { local: localHash, chain: onChainHash })

  const { valid, rejected } = await validSignatures(proposal.signatures || [], localHash, owners)

  // Step 5: what the page shows. Addresses in full and checksummed, never truncated.
  const display = {
    ...describe({ proposal, tx, token, chain }),
    network: chain.name,
    chainId: chain.chainId,
    safeAddress: getAddress(safe),
    to: getAddress(tx.to),
    value: tx.value.toString(),
    data: tx.data,
    operation: "CALL",
    nonce: tx.nonce.toString(),
    chainNonce: chainNonce.toString(),
    threshold: threshold.toString(),
    signatureCount: String(valid.length),
    domainHash: domainHash({ chainId: chain.chainId, safe }),
    messageHash: messageHash(tx),
    safeTxHash: localHash
  }

  return { tx, safe, hash: localHash, owners, threshold, chainNonce, valid, rejected, display }
}

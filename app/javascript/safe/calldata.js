// Rebuilds to, value and data from typed parameters, with the same refusals and codes as
// Chain::ProposalBuilder in Ruby. Any byte of difference from the server blocks signing.
// prevOwner comes from live getOwners only, and is never accepted as a parameter.
import { encodeFunctionData, isAddress } from "viem"
import { refuse } from "wallet/errors"
import { ERC20_ABI, SAFE_ABI } from "safe/abi"
import { SENTINEL_OWNERS, UINT256_MAX, ZERO_ADDRESS } from "safe/constants"

const ALLOWED_PARAMS = Object.freeze({
  transfer_token: ["recipient", "amount"],
  transfer_native: ["recipient", "amount"],
  add_owner: ["owner", "threshold"],
  remove_owner: ["owner", "threshold"],
  swap_owner: ["old_owner", "new_owner"],
  change_threshold: ["threshold"],
  rejection: ["nonce"]
})

export const PROPOSAL_KINDS = Object.freeze(Object.keys(ALLOWED_PARAMS))

export function prevOwnerOf(owners, owner) {
  const index = owners.indexOf(owner)
  if (index === -1) throw refuse("owner_unknown", { owner })
  return index === 0 ? SENTINEL_OWNERS : owners[index - 1]
}

function parseParamAddress(value) {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value) || !isAddress(value, { strict: true })) {
    throw refuse("invalid_address", { value })
  }
  return value.toLowerCase()
}

function parseOwner(value, safe) {
  const owner = parseParamAddress(value)
  if (owner === ZERO_ADDRESS || owner === SENTINEL_OWNERS || owner === safe) throw refuse("owner_forbidden", { owner })
  return owner
}

function parseRecipient(value, forbidden) {
  const recipient = parseParamAddress(value)
  if (recipient === ZERO_ADDRESS || recipient === SENTINEL_OWNERS || forbidden.includes(recipient)) {
    throw refuse("recipient_forbidden", { recipient })
  }
  return recipient
}

function parseAmount(value) {
  if (typeof value !== "string" || !/^[1-9][0-9]*$/.test(value)) throw refuse("invalid_amount", { value })
  const amount = BigInt(value)
  if (amount > UINT256_MAX) throw refuse("invalid_amount", { value })
  return amount
}

function parseThreshold(value, maximum) {
  const isInteger = (typeof value === "number" && Number.isSafeInteger(value)) ||
    (typeof value === "string" && /^[0-9]+$/.test(value))
  if (!isInteger) throw refuse("threshold_out_of_range", { value })
  const threshold = BigInt(value)
  if (threshold < 1n || threshold > BigInt(maximum)) throw refuse("threshold_out_of_range", { value: String(value), maximum })
  return threshold
}

function selfCall(safe, functionName, args) {
  return { to: safe, value: 0n, data: encodeFunctionData({ abi: SAFE_ABI, functionName, args }), operation: 0 }
}

// context: { safe, token, owners, threshold, currentNonce }. owners, threshold, currentNonce are live.
export function buildAction({ kind, params, nonce = null }, { safe, token = null, owners = [], threshold = null, currentNonce = null }) {
  const allowed = ALLOWED_PARAMS[kind]
  if (!Object.hasOwn(ALLOWED_PARAMS, kind)) throw refuse("unknown_kind", { kind })
  if (!params || typeof params !== "object") throw refuse("proposal_malformed")
  const extra = Object.keys(params).filter((key) => !allowed.includes(key))
  if (extra.length > 0) throw refuse("unexpected_param", { params: extra })

  switch (kind) {
    case "transfer_token": {
      if (!token) throw refuse("token_not_allowed")
      const recipient = parseRecipient(params.recipient, [safe, token])
      return { to: token, value: 0n, data: encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [recipient, parseAmount(params.amount)] }), operation: 0 }
    }
    case "transfer_native": {
      const recipient = parseRecipient(params.recipient, [safe])
      return { to: recipient, value: parseAmount(params.amount), data: "0x", operation: 0 }
    }
    case "add_owner": {
      const owner = parseOwner(params.owner, safe)
      if (owners.includes(owner)) throw refuse("owner_exists", { owner })
      return selfCall(safe, "addOwnerWithThreshold", [owner, parseThreshold(params.threshold, owners.length + 1)])
    }
    case "remove_owner": {
      const owner = parseOwner(params.owner, safe)
      const prev = prevOwnerOf(owners, owner)
      if (owners.length === 1) throw refuse("last_owner", { owner })
      return selfCall(safe, "removeOwner", [prev, owner, parseThreshold(params.threshold, owners.length - 1)])
    }
    case "swap_owner": {
      const oldOwner = parseParamAddress(params.old_owner)
      const newOwner = parseOwner(params.new_owner, safe)
      const prev = prevOwnerOf(owners, oldOwner)
      if (owners.includes(newOwner)) throw refuse("owner_exists", { owner: newOwner })
      return selfCall(safe, "swapOwner", [prev, oldOwner, newOwner])
    }
    case "change_threshold": {
      const next = parseThreshold(params.threshold, owners.length)
      if (threshold !== null && next === BigInt(threshold)) throw refuse("threshold_unchanged")
      return selfCall(safe, "changeThreshold", [next])
    }
    case "rejection": {
      if (typeof params.nonce !== "string" || !/^(0|[1-9][0-9]*)$/.test(params.nonce)) throw refuse("invalid_nonce", { nonce: params.nonce })
      const target = BigInt(params.nonce)
      if (currentNonce !== null && target < BigInt(currentNonce)) throw refuse("nonce_too_low", { nonce: params.nonce })
      if (nonce !== null && target !== BigInt(nonce)) throw refuse("invalid_nonce", { nonce: params.nonce })
      return { to: safe, value: 0n, data: "0x", operation: 0 }
    }
    default:
      throw refuse("unknown_kind", { kind })
  }
}

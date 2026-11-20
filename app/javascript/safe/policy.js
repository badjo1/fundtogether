// Refusals, mirroring Chain::SafePolicy in Ruby with the same vectors and the same codes.
// Takes the raw JSON field shape of a proposal, because a malformed field is itself a refusal.
// Order, first failure wins: operation, safe_tx_gas, base_gas, gas_price, gas_token, refund_receiver,
// nonce, target rules.
import { decodeFunctionData, encodeFunctionData } from "viem"
import { refuse } from "wallet/errors"
import { ERC20_ABI, SAFE_ABI } from "safe/abi"
import { SENTINEL_OWNERS, ZERO_ADDRESS } from "safe/constants"

const OWNER_SELECTORS = new Set(["0x0d582f13", "0xf8dc5dd9", "0xe318b52b", "0x694e80c3"])
const TRANSFER_SELECTOR = "0xa9059cbb"
const HEX_DATA = /^0x([0-9a-f]{2})*$/
const ADDRESS = /^0x[0-9a-f]{40}$/

function isZeroUint(value) {
  return value === 0 || value === "0"
}

// Non-canonical encodings (dirty padding, trailing bytes) fail the byte comparison after re-encoding.
function decodeExact(abi, data) {
  try {
    const { functionName, args } = decodeFunctionData({ abi, data })
    return encodeFunctionData({ abi, functionName, args }).toLowerCase() === data ? { functionName, args } : null
  } catch {
    return null
  }
}

function assertOwnerCall(data) {
  const decoded = decodeExact(SAFE_ABI, data)
  if (!decoded) throw refuse("malformed_calldata", { selector: data.slice(0, 10) })
  const args = decoded.args.map((arg) => (typeof arg === "string" ? arg.toLowerCase() : arg))
  const check = {
    addOwnerWithThreshold: ([owner, threshold]) => validOwner(owner) && threshold > 0n,
    removeOwner: ([prev, owner, threshold]) => validPrev(prev) && validOwner(owner) && threshold > 0n,
    swapOwner: ([prev, oldOwner, newOwner]) => validPrev(prev) && validOwner(oldOwner) && validOwner(newOwner),
    changeThreshold: ([threshold]) => threshold > 0n
  }[decoded.functionName]
  if (!check || !check(args)) throw refuse("malformed_calldata", { functionName: decoded.functionName })
}

function validOwner(address) {
  return address !== ZERO_ADDRESS && address !== SENTINEL_OWNERS
}

function validPrev(address) {
  return address !== ZERO_ADDRESS
}

function assertTokenTransfer(data) {
  const decoded = decodeExact(ERC20_ABI, data)
  if (!decoded || decoded.functionName !== "transfer") throw refuse("malformed_calldata")
  const [recipient, amount] = decoded.args
  if (recipient.toLowerCase() === ZERO_ADDRESS || amount === 0n) throw refuse("malformed_calldata")
}

function parseValue(value) {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value)) throw refuse("proposal_malformed", { field: "value" })
  return BigInt(value)
}

function assertTarget(tx, { safe, token }) {
  const to = typeof tx.to === "string" ? tx.to : ""
  if (!ADDRESS.test(to) || to === ZERO_ADDRESS || to === SENTINEL_OWNERS) throw refuse("to_forbidden", { to: tx.to })
  const data = tx.data
  if (typeof data !== "string" || !HEX_DATA.test(data)) throw refuse("malformed_calldata")
  const value = parseValue(tx.value)
  const selector = data.slice(0, 10)

  if (to === safe) {
    if (value !== 0n) throw refuse("self_call_value")
    if (data === "0x") return "rejection"
    if (!OWNER_SELECTORS.has(selector)) throw refuse("self_call_forbidden", { selector })
    assertOwnerCall(data)
    return "owner_call"
  }

  if (token && to === token) {
    if (selector !== TRANSFER_SELECTOR) throw refuse("token_call_forbidden", { selector })
    if (value !== 0n) throw refuse("token_call_value")
    assertTokenTransfer(data)
    return "token_transfer"
  }

  if (data !== "0x") throw refuse("unknown_target_data", { to, selector })
  if (value === 0n) throw refuse("empty_call", { to })
  return "native_transfer"
}

// fields: { to, value, data, operation, safe_tx_gas, base_gas, gas_price, gas_token, refund_receiver, nonce }
export function assertPolicy(fields, { safe, token = null, currentNonce = null }) {
  if (!isZeroUint(fields.operation)) throw refuse("operation_not_call", { operation: fields.operation })
  if (!isZeroUint(fields.safe_tx_gas)) throw refuse("safe_tx_gas_nonzero")
  if (!isZeroUint(fields.base_gas)) throw refuse("base_gas_nonzero")
  if (!isZeroUint(fields.gas_price)) throw refuse("gas_price_nonzero")
  if (fields.gas_token !== ZERO_ADDRESS) throw refuse("gas_token_nonzero")
  if (fields.refund_receiver !== ZERO_ADDRESS) throw refuse("refund_receiver_nonzero")

  if (typeof fields.nonce !== "string" || !/^(0|[1-9][0-9]*)$/.test(fields.nonce)) throw refuse("invalid_nonce", { nonce: fields.nonce })
  if (currentNonce !== null && BigInt(fields.nonce) < currentNonce) {
    throw refuse("nonce_too_low", { nonce: fields.nonce, currentNonce: currentNonce.toString() })
  }

  return assertTarget(fields, { safe, token })
}

// At creation: at least 1, at most owner count. n-of-n and 1-of-n with n > 1 need an acknowledgement.
export function assertThresholdRules({ ownerCount, threshold, acknowledged = false }) {
  const count = BigInt(ownerCount)
  const value = BigInt(threshold)
  if (value < 1n || value > count) throw refuse("threshold_out_of_range")
  if (count > 1n && (value === count || value === 1n) && !acknowledged) throw refuse("risk_not_acknowledged")
}

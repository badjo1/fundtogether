// Recomputes the initializer and CREATE2 address from owners, threshold and salt nonce, and refuses
// any difference from the server. See docs/research/safe-integration.md, section 4.
import { concat, encodeAbiParameters, encodeFunctionData, getAddress, getCreate2Address, keccak256 } from "viem"
import { refuse } from "wallet/errors"
import { FACTORY_ABI, SAFE_ABI } from "safe/abi"
import {
  FALLBACK_HANDLER, PROXY_CREATION_CODE, SAFE_L2_SINGLETON, SAFE_PROXY_FACTORY, SENTINEL_OWNERS, ZERO_ADDRESS
} from "safe/constants"
import { parseAddress, parseHexData, parseSmallUint, parseUintString } from "safe/values"

export function buildInitializer({ owners, threshold, fallbackHandler = FALLBACK_HANDLER }) {
  return encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "setup",
    args: [owners, threshold, ZERO_ADDRESS, "0x", fallbackHandler, ZERO_ADDRESS, 0n, ZERO_ADDRESS]
  })
}

export function predictSafeAddress({ initializer, saltNonce, singleton = SAFE_L2_SINGLETON, factory = SAFE_PROXY_FACTORY }) {
  const salt = keccak256(concat([keccak256(initializer), encodeAbiParameters([{ type: "uint256" }], [saltNonce])]))
  const bytecode = concat([PROXY_CREATION_CODE, encodeAbiParameters([{ type: "uint256" }], [BigInt(singleton)])])
  return getCreate2Address({ from: getAddress(factory), salt, bytecode }).toLowerCase()
}

export function buildDeployCalldata({ initializer, saltNonce }) {
  return encodeFunctionData({
    abi: FACTORY_ABI,
    functionName: "createProxyWithNonce",
    args: [SAFE_L2_SINGLETON, initializer, saltNonce]
  })
}

function parseOwners(list) {
  if (!Array.isArray(list) || list.length === 0) throw refuse("deployment_malformed", { reason: "owners" })
  const owners = list.map((owner) => parseAddress(owner, "deployment_malformed"))
  if (new Set(owners).size !== owners.length) throw refuse("deployment_malformed", { reason: "duplicate owner" })
  if (owners.some((owner) => owner === ZERO_ADDRESS || owner === SENTINEL_OWNERS)) {
    throw refuse("deployment_malformed", { reason: "reserved owner" })
  }
  return owners
}

// Returns the verified, parsed deployment. `intent` is what the user chose on the page, if known.
export function verifyDeployment(deployment, { chainId, intent = null }) {
  if (!deployment || typeof deployment !== "object") throw refuse("deployment_malformed")
  if (Number(deployment.chain_id) !== chainId) throw refuse("proposal_chain_mismatch")

  if (parseAddress(deployment.factory, "deployment_malformed") !== SAFE_PROXY_FACTORY ||
      parseAddress(deployment.singleton, "deployment_malformed") !== SAFE_L2_SINGLETON ||
      parseAddress(deployment.fallback_handler, "deployment_malformed") !== FALLBACK_HANDLER) {
    throw refuse("deployment_contract_mismatch")
  }

  const owners = parseOwners(deployment.owners)
  const threshold = parseSmallUint(deployment.threshold, "deployment_malformed")
  if (threshold < 1n || threshold > BigInt(owners.length)) throw refuse("threshold_out_of_range")
  const saltNonce = parseUintString(deployment.salt_nonce, "deployment_malformed")

  if (intent) {
    const chosen = intent.owners.map((owner) => parseAddress(owner, "deployment_malformed"))
    const sameOwners = chosen.length === owners.length && chosen.every((owner) => owners.includes(owner))
    if (!sameOwners || parseSmallUint(intent.threshold, "deployment_malformed") !== threshold) {
      throw refuse("deployment_intent_mismatch")
    }
  }

  const initializer = buildInitializer({ owners, threshold })
  if (parseHexData(deployment.initializer, "deployment_malformed") !== initializer.toLowerCase()) {
    throw refuse("initializer_mismatch")
  }

  const safeAddress = predictSafeAddress({ initializer, saltNonce })
  if (parseAddress(deployment.safe_address, "deployment_malformed") !== safeAddress) {
    throw refuse("address_mismatch", { expected: safeAddress })
  }

  return { owners, threshold, saltNonce, initializer, safeAddress, data: buildDeployCalldata({ initializer, saltNonce }) }
}

// The same live checks the server runs before calling a fund active. A module can move funds without
// signatures, and a guard can block all execution.
export async function verifyDeployedSafe(reader, { safeAddress, owners, threshold }) {
  if (!await reader.hasCode(safeAddress)) throw refuse("deployed_state_mismatch", { reason: "no code" })
  if (await reader.singleton(safeAddress) !== SAFE_L2_SINGLETON) throw refuse("deployed_state_mismatch", { reason: "singleton" })

  const liveOwners = await reader.owners(safeAddress)
  if (liveOwners.length !== owners.length || liveOwners.some((owner, index) => owner !== owners[index])) {
    throw refuse("deployed_state_mismatch", { reason: "owners" })
  }
  if (await reader.threshold(safeAddress) !== threshold) throw refuse("deployed_state_mismatch", { reason: "threshold" })
  if ((await reader.modules(safeAddress)).length > 0) throw refuse("deployed_state_mismatch", { reason: "modules" })
  if (await reader.guard(safeAddress) !== ZERO_ADDRESS) throw refuse("deployed_state_mismatch", { reason: "guard" })
  if (await reader.fallbackHandler(safeAddress) !== FALLBACK_HANDLER) throw refuse("deployed_state_mismatch", { reason: "fallback handler" })
}

// An in-memory Safe and token behind the EIP-1193 surface. It answers from its own state and signs
// through viem with the publicly known test keys. It is a test double for flows, not a simulator:
// real bytecode behaviour is covered by the research sims and the later live end-to-end run.
import { decodeFunctionData, encodeFunctionResult, getAddress } from "./viem_helpers.js"
import { privateKeyToAccount } from "./vendor/viem_accounts.js"
import { ERC20_ABI, FACTORY_ABI, SAFE_ABI } from "safe/abi"
import { FALLBACK_HANDLER, FALLBACK_SLOT, GUARD_SLOT, SAFE_L2_SINGLETON, SAFE_PROXY_FACTORY, TOPICS, ZERO_WORD } from "safe/constants"
import { safeTxHash } from "safe/hash"
import { MockProvider, providerError } from "./mock_provider.mjs"

export const KEYS = {
  one: { key: "0x0000000000000000000000000000000000000000000000000000000000000001", address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf" },
  two: { key: "0x0000000000000000000000000000000000000000000000000000000000000002", address: "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf" },
  three: { key: "0x0000000000000000000000000000000000000000000000000000000000000003", address: "0x6813eb9362372eef6200f3b1dbc3f819671cba69" },
  four: { key: "0x0000000000000000000000000000000000000000000000000000000000000004", address: "0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718" }
}

export const CHAIN_CONFIG = {
  chain_id: 11155111,
  name: "Sepolia",
  native_symbol: "ETH",
  explorer_url: "https://sepolia.etherscan.io",
  rpc_urls: ["https://rpc.invalid"],
  token: { symbol: "EURC", address: "0x08210f9170f89ab7658f0b5e3ff39b0e03c594d4", decimals: 6 }
}

export const SAFE = "0x1111111111111111111111111111111111111111"
export const TOKEN = CHAIN_CONFIG.token.address

function word(address) {
  return `0x${address.slice(2).padStart(64, "0")}`
}

export function fakeChain(overrides = {}) {
  const state = {
    chainId: 11155111,
    safe: SAFE,
    owners: [KEYS.one.address, KEYS.two.address, KEYS.three.address],
    threshold: 2n,
    nonce: 5n,
    singleton: SAFE_L2_SINGLETON,
    fallbackHandler: FALLBACK_HANDLER,
    guard: "0x0000000000000000000000000000000000000000",
    modules: [],
    code: new Set([SAFE]),
    tokenDecimals: 6,
    tokenBalances: new Map([[SAFE, 10n ** 12n]]),
    nativeBalance: 10n ** 18n,
    gasEstimate: 100_000n,
    gasPrice: 1_000_000_000n,
    active: KEYS.one,
    onChainHash: null,
    receipts: new Map(),
    transactions: new Map(),
    sent: [],
    signed: [],
    signatureOverride: null,
    estimateError: null,
    onSend: null,
    ...overrides
  }

  function answerEthCall([{ to, data }]) {
    const target = to.toLowerCase()
    if (target === TOKEN) {
      const { functionName, args } = decodeFunctionData({ abi: ERC20_ABI, data })
      const result = functionName === "decimals" ? state.tokenDecimals : state.tokenBalances.get(args[0].toLowerCase()) ?? 0n
      return encodeFunctionResult({ abi: ERC20_ABI, functionName, result })
    }
    if (target === SAFE_PROXY_FACTORY) {
      if (state.simulatedProxy === undefined) throw providerError(-32000, "execution reverted: Create2 call failed")
      return encodeFunctionResult({ abi: FACTORY_ABI, functionName: "createProxyWithNonce", result: getAddress(state.simulatedProxy) })
    }
    if (!state.code.has(target)) return "0x"

    const { functionName, args } = decodeFunctionData({ abi: SAFE_ABI, data })
    switch (functionName) {
      case "getOwners":
        return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: state.owners.map((owner) => getAddress(owner)) })
      case "getThreshold":
        return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: state.threshold })
      case "nonce":
        return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: state.nonce })
      case "getModulesPaginated":
        return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: [state.modules, "0x0000000000000000000000000000000000000001"] })
      case "getTransactionHash": {
        if (state.onChainHash) return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: state.onChainHash })
        const [txTo, value, txData, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce] = args
        const tx = {
          to: txTo.toLowerCase(), value, data: txData, operation, safeTxGas, baseGas, gasPrice,
          gasToken: gasToken.toLowerCase(), refundReceiver: refundReceiver.toLowerCase(), nonce
        }
        return encodeFunctionResult({ abi: SAFE_ABI, functionName, result: safeTxHash({ chainId: state.chainId, safe: target, tx }) })
      }
      default:
        throw providerError(-32000, `unexpected call ${functionName}`)
    }
  }

  const account = () => privateKeyToAccount(state.active.key)

  const provider = new MockProvider({
    eth_chainId: () => `0x${state.chainId.toString(16)}`,
    eth_accounts: () => [state.active.address],
    eth_requestAccounts: () => [state.active.address],
    eth_call: answerEthCall,
    eth_getCode: ([address]) => (state.code.has(address.toLowerCase()) ? "0x6080" : "0x"),
    eth_getStorageAt: ([, slot]) => {
      if (slot === "0x0") return word(state.singleton)
      if (slot === GUARD_SLOT) return word(state.guard)
      if (slot === FALLBACK_SLOT) return word(state.fallbackHandler)
      return ZERO_WORD
    },
    eth_getBalance: () => `0x${state.nativeBalance.toString(16)}`,
    eth_gasPrice: () => `0x${state.gasPrice.toString(16)}`,
    eth_estimateGas: () => {
      if (state.estimateError) throw state.estimateError
      return `0x${state.gasEstimate.toString(16)}`
    },
    eth_getTransactionReceipt: ([hash]) => state.receipts.get(hash) ?? null,
    eth_getTransactionByHash: ([hash]) => state.transactions.get(hash) ?? null,
    eth_signTypedData_v4: async ([address, json]) => {
      const typed = JSON.parse(json)
      state.signed.push({ address, typed })
      if (state.signatureOverride) return state.signatureOverride(typed)
      return account().signTypedData(typed)
    },
    personal_sign: async ([message, address]) => {
      state.signed.push({ address, message })
      return account().signMessage({ message: { raw: message } })
    },
    eth_sendTransaction: async ([tx]) => {
      state.sent.push(tx)
      const hash = `0x${String(state.sent.length).padStart(64, "a")}`
      state.transactions.set(hash, { hash })
      if (state.onSend) state.onSend(tx, hash)
      return hash
    }
  })

  return { state, provider }
}

export function executionReceipt({ safe = SAFE, hash, topic = TOPICS.executionSuccess, status = "0x1" }) {
  return { status, logs: status === "0x1" ? [{ address: safe, topics: [topic, hash], data: "0x" }] : [] }
}

export function signProposalHash(key, typed) {
  return privateKeyToAccount(key).signTypedData(typed)
}

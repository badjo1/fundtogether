// TEST ONLY: never import from app/javascript (test/javascript/isolation.test.mjs asserts this).
// An injected EIP-1193 wallet with EIP-6963 announce, for the live end-to-end run. It signs locally
// with keys handed in at runtime and forwards reads to an RPC. Keys come from a path outside the repo
// and are never hard-coded here. Sending transactions is off unless allowSend is set.
import { privateKeyToAccount } from "./vendor/viem_accounts.js"

const FORWARDED_READS = new Set([
  "eth_blockNumber", "eth_call", "eth_estimateGas", "eth_feeHistory", "eth_gasPrice", "eth_getBalance", "eth_getBlockByNumber",
  "eth_getCode", "eth_getLogs", "eth_getStorageAt", "eth_getTransactionByHash", "eth_getTransactionCount",
  "eth_getTransactionReceipt", "eth_maxPriorityFeePerGas", "net_version"
])

function rpcError(code, message) {
  return Object.assign(new Error(message), { code })
}

function toHexChain(chainId) {
  return `0x${chainId.toString(16)}`
}

export class TestProvider {
  constructor({ privateKeys, chains, chainId, allowSend = false, fetch: fetchFn = globalThis.fetch?.bind(globalThis) }) {
    if (!Array.isArray(privateKeys) || privateKeys.length === 0) throw new Error("TestProvider needs keys at runtime")
    this.accounts = privateKeys.map((key) => privateKeyToAccount(key))
    this.chains = new Map(Object.entries(chains).map(([id, url]) => [Number(id), url]))
    this.chainId = chainId
    this.allowSend = allowSend
    this.fetch = fetchFn
    this.index = 0
    this.authorized = false
    this.listeners = new Map()
    this.rpcId = 0
    this.nextFailure = null
    this.log = []
    this.isTestProvider = true
  }

  get account() {
    return this.accounts[this.index]
  }

  // --- Controls for the e2e driver

  selectAccount(index) {
    this.index = index
    this.emit("accountsChanged", [this.account.address.toLowerCase()])
  }

  selectChain(chainId) {
    this.chainId = chainId
    this.emit("chainChanged", toHexChain(chainId))
  }

  // The next wallet prompt fails with this code: 4001 reject, -32002 busy, and so on.
  failNext(code, message = "test provider failure") {
    this.nextFailure = rpcError(code, message)
  }

  // --- EIP-1193

  on(event, listener) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set())
    this.listeners.get(event).add(listener)
  }

  removeListener(event, listener) {
    this.listeners.get(event)?.delete(listener)
  }

  emit(event, payload) {
    this.listeners.get(event)?.forEach((listener) => listener(payload))
  }

  async request({ method, params = [] }) {
    this.log.push({ method })
    switch (method) {
      case "eth_chainId":
        return toHexChain(this.chainId)
      case "eth_accounts":
        return this.authorized ? [this.account.address.toLowerCase()] : []
      case "eth_requestAccounts":
        this.takeFailure()
        this.authorized = true
        return [this.account.address.toLowerCase()]
      case "wallet_switchEthereumChain":
        return this.switchChain(params[0])
      case "wallet_addEthereumChain":
        return this.addChain(params[0])
      case "personal_sign":
        this.takeFailure()
        this.assertCurrent(params[1])
        return this.account.signMessage({ message: { raw: params[0] } })
      case "eth_signTypedData_v4":
        this.takeFailure()
        this.assertCurrent(params[0])
        return this.account.signTypedData(JSON.parse(params[1]))
      case "eth_sendTransaction":
        this.takeFailure()
        return this.sendTransaction(params[0])
      default:
        if (FORWARDED_READS.has(method)) return this.rpc(method, params)
        throw rpcError(4200, `Unsupported method: ${method}`)
    }
  }

  takeFailure() {
    if (!this.nextFailure) return
    const failure = this.nextFailure
    this.nextFailure = null
    throw failure
  }

  assertCurrent(address) {
    if (String(address).toLowerCase() !== this.account.address.toLowerCase()) throw rpcError(4100, "Not the active account")
  }

  switchChain({ chainId }) {
    this.takeFailure()
    const target = Number(chainId)
    if (!this.chains.has(target)) throw rpcError(4902, "Unrecognized chain ID")
    this.selectChain(target)
    return null
  }

  addChain({ chainId, rpcUrls }) {
    this.takeFailure()
    this.chains.set(Number(chainId), rpcUrls[0])
    return null
  }

  async sendTransaction(tx) {
    if (!this.allowSend) throw rpcError(4200, "TestProvider: sending is off. Pass allowSend for a live run.")
    this.assertCurrent(tx.from)
    const [nonce, gasPrice] = await Promise.all([
      this.rpc("eth_getTransactionCount", [this.account.address, "pending"]),
      this.rpc("eth_gasPrice", [])
    ])
    const gas = tx.gas ?? await this.rpc("eth_estimateGas", [tx])
    const raw = await this.account.signTransaction({
      type: "legacy",
      chainId: this.chainId,
      to: tx.to,
      data: tx.data ?? "0x",
      value: BigInt(tx.value ?? "0x0"),
      gas: BigInt(gas),
      gasPrice: BigInt(gasPrice),
      nonce: Number(nonce)
    })
    return this.rpc("eth_sendRawTransaction", [raw])
  }

  async rpc(method, params) {
    const url = this.chains.get(this.chainId)
    if (!url) throw rpcError(4901, "No RPC for this chain")
    this.rpcId += 1
    const response = await this.fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: this.rpcId, method, params })
    })
    const payload = await response.json()
    if (payload.error) throw Object.assign(new Error(payload.error.message), { code: payload.error.code, data: payload.error.data })
    return payload.result
  }
}

// Answers eip6963:requestProvider and announces once at install, as real extensions do.
export function installTestProvider(win, provider, info = {}) {
  const detail = Object.freeze({
    info: Object.freeze({
      uuid: info.uuid ?? "00000000-0000-4000-8000-000000000001",
      name: info.name ?? "FundTogether Test Wallet",
      icon: info.icon ?? "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E",
      rdns: info.rdns ?? "nl.fundtogether.test"
    }),
    provider
  })
  const announce = () => win.dispatchEvent(new win.CustomEvent("eip6963:announceProvider", { detail }))
  win.addEventListener("eip6963:requestProvider", announce)
  announce()
  return () => win.removeEventListener("eip6963:requestProvider", announce)
}

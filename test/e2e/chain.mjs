// Independent view of the chain, for verification and for hand-built transactions. Deliberately shares
// nothing with the app: raw JSON-RPC, selectors written out, its own encoder. Keys come from a path in
// the environment and never leave this process except as signed transactions.
import { readFileSync, writeFileSync, existsSync, chmodSync } from "node:fs"
import { randomBytes } from "node:crypto"
import { resolve } from "node:path"

export const CHAIN_ID = 11155111
export const CHAIN_HEX = "0xaa36a7"
export const SINGLETON = "0x29fcb43b46531bca003ddc8fcb67ffe91900c762"
export const FACTORY = "0x4e1dcf7ad4e460cfd30791ccc4f9c8a4f820ec67"
export const FALLBACK = "0xfd0732dc9e303f09fcef3a7388ad10a83459ec99"
export const EURC = "0x08210f9170f89ab7658f0b5e3ff39b0e03c594d4"
export const ZERO = `0x${"0".repeat(40)}`
export const MAX_SPEND_WEI = BigInt(process.env.FT_E2E_MAX_SPEND_WEI || "30000000000000000") // 0.03 ETH by default: stop and report beyond this.
export const RPC_URLS = ["https://ethereum-sepolia-rpc.publicnode.com", "https://sepolia.gateway.tenderly.co", "https://rpc.sepolia.ethpandaops.io"]
export const EXPLORER = "https://sepolia.etherscan.io"
export const ROOT = new URL("../..", import.meta.url).pathname.replace(/\/$/, "")

const SEL = {
  getOwners: "0xa0e67e2b", getThreshold: "0xe75235b8", nonce: "0xaffed0e0", getModulesPaginated: "0xcc2f8452",
  VERSION: "0xffa1ad74", balanceOf: "0x70a08231", getTransactionHash: "0xd8d11f78", execTransaction: "0x6a761202",
  createProxyWithNonce: "0x1688f0b9"
}
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8"
const FALLBACK_SLOT = "0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5"
export const TOPICS = {
  ExecutionSuccess: "0x442e715f626346e8c54381002da614f62bee8d27386535b2521ec8540898556e",
  ExecutionFailure: "0x23428b18acfb3ea64b08dc0c1d296ea9c09702c09083ca5272e64d115b687d23"
}

export class RevertError extends Error {
  constructor(message, data) { super(message); this.data = data; this.reason = decodeRevert(data) || message }
}

export function decodeRevert(data) {
  if (typeof data !== "string" || !data.startsWith("0x08c379a0")) return null
  const length = Number(BigInt(`0x${data.slice(74, 138)}`))
  return Buffer.from(data.slice(138, 138 + length * 2), "hex").toString("utf8")
}

let rpcId = 0
export async function rpc(method, params = [], { urls = RPC_URLS } = {}) {
  let last
  for (const url of urls) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(20000), method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }), signal: AbortSignal.timeout(20000) })
        if (response.status === 429 || response.status >= 500) throw new Error(`http ${response.status}`)
        const payload = await response.json()
        if (payload.error) {
          const isRevert = /revert/i.test(payload.error.message || "") || payload.error.data
          if (isRevert) throw new RevertError(payload.error.message, payload.error.data)
          throw new Error(`${method}: ${payload.error.message}`)
        }
        return payload.result
      } catch (error) {
        if (error instanceof RevertError) throw error
        last = error
      }
    }
  }
  throw last
}

export async function assertSepolia() {
  const id = await rpc("eth_chainId")
  if (id !== CHAIN_HEX) throw new Error(`ABORT: chain ${id}, expected ${CHAIN_HEX}. Nothing sent.`)
}

const word = (value) => BigInt(value).toString(16).padStart(64, "0")
const addr = (address) => address.slice(2).toLowerCase().padStart(64, "0")
const strip = (hex) => (hex || "0x").slice(2)
const call = (to, data) => rpc("eth_call", [{ to, data }, "latest"])

export const read = {
  owners: async (safe) => {
    const hex = strip(await call(safe, SEL.getOwners))
    const count = Number(BigInt(`0x${hex.slice(64, 128)}`))
    return Array.from({ length: count }, (_, i) => `0x${hex.slice(128 + i * 64 + 24, 128 + (i + 1) * 64)}`)
  },
  threshold: async (safe) => Number(BigInt(await call(safe, SEL.getThreshold))),
  nonce: async (safe) => Number(BigInt(await call(safe, SEL.nonce))),
  version: async (safe) => {
    const hex = strip(await call(safe, SEL.VERSION))
    const length = Number(BigInt(`0x${hex.slice(64, 128)}`))
    return Buffer.from(hex.slice(128, 128 + length * 2), "hex").toString()
  },
  singleton: async (safe) => `0x${(await rpc("eth_getStorageAt", [safe, "0x0", "latest"])).slice(-40)}`,
  guard: async (safe) => `0x${(await rpc("eth_getStorageAt", [safe, GUARD_SLOT, "latest"])).slice(-40)}`,
  fallback: async (safe) => `0x${(await rpc("eth_getStorageAt", [safe, FALLBACK_SLOT, "latest"])).slice(-40)}`,
  modules: async (safe) => {
    const hex = strip(await call(safe, `${SEL.getModulesPaginated}${addr("0x0000000000000000000000000000000000000001")}${word(10)}`))
    return Number(BigInt(`0x${hex.slice(128, 192)}`))
  },
  balance: async (address) => BigInt(await rpc("eth_getBalance", [address, "latest"])),
  eurc: async (address) => BigInt(await call(EURC, `${SEL.balanceOf}${addr(address)}`)),
  code: (address) => rpc("eth_getCode", [address, "latest"]),
  txCount: async (address) => Number(BigInt(await rpc("eth_getTransactionCount", [address, "latest"]))),
  receipt: (hash) => rpc("eth_getTransactionReceipt", [hash]),
  tx: (hash) => rpc("eth_getTransactionByHash", [hash])
}

export async function safeFacts(safe) {
  const [owners, threshold, nonce, version, singleton, guard, fallback, modules, code] = await Promise.all([
    read.owners(safe), read.threshold(safe), read.nonce(safe), read.version(safe), read.singleton(safe), read.guard(safe),
    read.fallback(safe), read.modules(safe), read.code(safe)
  ])
  return { owners, threshold, nonce, version, singleton, guard, fallback, modules, codeBytes: (code.length - 2) / 2 }
}

// execTransaction(to, value, data, 0, 0, 0, 0, 0, 0, signatures) by hand: ten head words, two tails.
export function encodeExec({ to, value = 0n, data = "0x", signatures }) {
  const body = strip(data)
  const sigs = strip(signatures)
  const pad = (hex) => hex.padEnd(Math.ceil(hex.length / 64) * 64, "0")
  const dataOffset = 32 * 10
  const sigOffset = dataOffset + 32 + pad(body).length / 2
  return SEL.execTransaction + addr(to) + word(value) + word(dataOffset) + word(0) + word(0) + word(0) + word(0) + addr(ZERO) + addr(ZERO) +
    word(sigOffset) + word(body.length / 2) + pad(body) + word(sigs.length / 2) + pad(sigs)
}

export function encodeTxHashCall({ to, value = 0n, data = "0x", nonce }) {
  const body = strip(data)
  const pad = body.padEnd(Math.ceil(body.length / 64) * 64, "0")
  return SEL.getTransactionHash + addr(to) + word(value) + word(32 * 10) + word(0) + word(0) + word(0) + word(0) + addr(ZERO) + addr(ZERO) +
    word(nonce) + word(body.length / 2) + pad
}

// Sorted ascending by signer, as the contract demands.
export function joinSignatures(list) {
  return `0x${[...list].sort((x, y) => (BigInt(x.signer) < BigInt(y.signer) ? -1 : 1)).map((entry) => strip(entry.signature)).join("")}`
}

export async function simulate({ from, to, data, value = "0x0" }) {
  try {
    const result = await rpc("eth_call", [{ from, to, data, value }, "latest"])
    return { ok: true, result }
  } catch (error) {
    if (error instanceof RevertError) return { ok: false, revert: error.reason }
    throw error
  }
}

// --- Keys. Paths only; contents never printed.

let identities
export function identity() {
  if (identities) return identities
  const path = process.env.FT_E2E_KEYS
  if (!path) throw new Error("set FT_E2E_KEYS to the keys file (outside the repo)")
  if (resolve(path).startsWith(`${ROOT}/`)) throw new Error("the keys file must be outside the repo")
  const list = JSON.parse(readFileSync(path, "utf8"))
  const pick = (role) => {
    const row = list.find((entry) => entry.role === role)
    return { address: row.address.toLowerCase(), key: row.private_key.startsWith("0x") ? row.private_key : `0x${row.private_key}`, funded: true }
  }
  const freshPath = `${process.env.FT_E2E_OUT}/fresh_keys.json`
  const fresh = existsSync(freshPath) ? JSON.parse(readFileSync(freshPath, "utf8")) : { d: `0x${randomBytes(32).toString("hex")}`, e: `0x${randomBytes(32).toString("hex")}`, f: `0x${randomBytes(32).toString("hex")}`, g: `0x${randomBytes(32).toString("hex")}` }
  if (!existsSync(freshPath)) { writeFileSync(freshPath, JSON.stringify(fresh), { mode: 0o600 }); chmodSync(freshPath, 0o600) }
  identities = { a: pick("funder-owner-a"), b: pick("owner-b"), c: pick("owner-c") }
  for (const name of Object.keys(fresh)) identities[name] = { key: fresh[name], address: null, funded: false }
  return identities
}

export function secrets() {
  return Object.values(identity()).flatMap(({ key }) => [key, key.slice(2)])
}

// viem's bundled account code, loaded as a data URL so no key material or copy lands on disk.
let accountsModule
export async function accountFor(name) {
  accountsModule ||= await import(`data:text/javascript;base64,${readFileSync(`${ROOT}/test/javascript/support/vendor/viem_accounts.js`).toString("base64")}`)
  const entry = identity()[name]
  const account = accountsModule.privateKeyToAccount(entry.key)
  entry.address = account.address.toLowerCase()
  return account
}

export async function addressOf(name) {
  return (await accountFor(name)).address.toLowerCase()
}

// --- Guarded sending

export async function totalFunded() {
  const { a, b, c } = identity()
  const balances = await Promise.all([a, b, c].map(({ address }) => read.balance(address)))
  return balances.reduce((sum, value) => sum + value, 0n)
}

export async function assertBudget(startTotal) {
  const spent = BigInt(startTotal) - await totalFunded()
  if (spent > MAX_SPEND_WEI) throw new Error(`STOP: spend ${spent} wei is over the limit of ${MAX_SPEND_WEI} wei`)
  return spent
}

export async function isCanonicalSafe(address) {
  return (await read.singleton(address)) === SINGLETON
}

// `to` must be a test address, the canonical factory, EURC, or a contract whose singleton is the canonical SafeL2.
async function assertAllowedTarget(to, value) {
  const target = to.toLowerCase()
  const { a, b, c } = identity()
  if ([a.address, b.address, c.address].includes(target)) return
  if (target === FACTORY || target === EURC) { if (BigInt(value) !== 0n) throw new Error("ABORT: value to a contract"); return }
  if (await isCanonicalSafe(target)) return
  throw new Error(`ABORT: ${target} is not on the allowlist. Nothing sent.`)
}

export async function send(name, { to, value = 0n, data = "0x", gas }, { startTotal } = {}) {
  await assertSepolia()
  await assertAllowedTarget(to, value)
  if (startTotal) await assertBudget(startTotal)
  const account = await accountFor(name)
  const [nonce, gasPrice] = await Promise.all([rpc("eth_getTransactionCount", [account.address, "pending"]), rpc("eth_gasPrice")])
  const limit = gas ? BigInt(gas) : (BigInt(await rpc("eth_estimateGas", [{ from: account.address, to, value: `0x${BigInt(value).toString(16)}`, data }])) * 13n) / 10n
  const raw = await account.signTransaction({ type: "legacy", chainId: CHAIN_ID, to, value: BigInt(value), data, gas: limit, gasPrice: BigInt(gasPrice) * 2n + 1000n, nonce: Number(nonce) })
  const hash = await rpc("eth_sendRawTransaction", [raw])
  const receipt = await waitReceipt(hash)
  return { hash, receipt }
}

export async function waitReceipt(hash, ms = 240000) {
  const end = Date.now() + ms
  while (Date.now() < end) {
    const receipt = await read.receipt(hash).catch(() => null)
    if (receipt) return receipt
    await new Promise((resolve) => setTimeout(resolve, 3000))
  }
  throw new Error(`no receipt for ${hash} within ${ms} ms`)
}

export const explorerTx = (hash) => `${EXPLORER}/tx/${hash}`
export const wei = (eth) => BigInt(Math.round(eth * 1e9)) * 1_000_000_000n

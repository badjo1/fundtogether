import "./support/register.mjs"
import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { fakeWindow, tick } from "./support/mock_provider.mjs"

const { TestProvider, installTestProvider } = await import("./support/test_provider.js")
const { CHAIN_CONFIG, KEYS } = await import("./support/fake_chain.js")
const { WalletSession } = await import("wallet/session")
const { normalizeChain } = await import("wallet/chains")
const { hashMessage, recoverAddress, hashTypedData } = await import("viem")

const CHAINS = { 11155111: "https://rpc.invalid" }

function create(options = {}) {
  const calls = []
  const fetchFn = async (url, request) => {
    const { method, params, id } = JSON.parse(request.body)
    calls.push({ url, method, params })
    const results = options.rpc ?? {}
    return { json: async () => ({ jsonrpc: "2.0", id, result: results[method] ?? "0x1" }) }
  }
  const provider = new TestProvider({
    privateKeys: [KEYS.one.key, KEYS.two.key],
    chains: CHAINS,
    chainId: 11155111,
    fetch: fetchFn,
    ...options
  })
  return { provider, calls }
}

describe("test provider", () => {
  test("needs keys at runtime", () => {
    assert.throws(() => new TestProvider({ privateKeys: [], chains: CHAINS, chainId: 1 }), /keys at runtime/)
  })

  test("accounts are empty until requested, like a real wallet", async () => {
    const { provider } = create()
    assert.deepEqual(await provider.request({ method: "eth_accounts" }), [])
    assert.deepEqual(await provider.request({ method: "eth_requestAccounts" }), [KEYS.one.address])
    assert.deepEqual(await provider.request({ method: "eth_accounts" }), [KEYS.one.address])
    assert.equal(await provider.request({ method: "eth_chainId" }), "0xaa36a7")
  })

  test("signs personal messages and typed data locally, and they recover", async () => {
    const { provider } = create()
    await provider.request({ method: "eth_requestAccounts" })
    const signature = await provider.request({ method: "personal_sign", params: ["0x68656c6c6f", KEYS.one.address] })
    assert.equal((await recoverAddress({ hash: hashMessage("hello"), signature })).toLowerCase(), KEYS.one.address)

    const typed = {
      types: {
        EIP712Domain: [{ name: "chainId", type: "uint256" }, { name: "verifyingContract", type: "address" }],
        Mail: [{ name: "amount", type: "uint256" }]
      },
      domain: { chainId: 11155111, verifyingContract: KEYS.three.address },
      primaryType: "Mail",
      message: { amount: "5" }
    }
    const typedSignature = await provider.request({ method: "eth_signTypedData_v4", params: [KEYS.one.address, JSON.stringify(typed)] })
    assert.equal((await recoverAddress({ hash: hashTypedData(typed), signature: typedSignature })).toLowerCase(), KEYS.one.address)
  })

  test("refuses to sign for an account that is not active", async () => {
    const { provider } = create()
    await assert.rejects(provider.request({ method: "personal_sign", params: ["0x00", KEYS.two.address] }), { code: 4100 })
  })

  test("forwards reads to the RPC and refuses anything else", async () => {
    const { provider, calls } = create({ rpc: { eth_getBalance: "0x10" } })
    assert.equal(await provider.request({ method: "eth_getBalance", params: [KEYS.one.address, "latest"] }), "0x10")
    assert.equal(calls[0].method, "eth_getBalance")
    await assert.rejects(provider.request({ method: "eth_sendRawTransaction", params: ["0x"] }), { code: 4200 })
    await assert.rejects(provider.request({ method: "eth_sign", params: [] }), { code: 4200 })
  })

  test("sending is off by default, so a stray run cannot spend", async () => {
    const { provider, calls } = create()
    await provider.request({ method: "eth_requestAccounts" })
    await assert.rejects(provider.request({ method: "eth_sendTransaction", params: [{ from: KEYS.one.address, to: KEYS.two.address }] }), /sending is off/)
    assert.equal(calls.length, 0)
  })

  test("with allowSend it signs legacy and hands a raw tx to the RPC; nothing is really sent here", async () => {
    const { provider, calls } = create({ allowSend: true, rpc: { eth_getTransactionCount: "0x3", eth_gasPrice: "0x3b9aca00", eth_sendRawTransaction: "0xhash" } })
    await provider.request({ method: "eth_requestAccounts" })
    const hash = await provider.request({ method: "eth_sendTransaction", params: [{ from: KEYS.one.address, to: KEYS.two.address, data: "0x", value: "0x0", gas: "0x5208" }] })
    assert.equal(hash, "0xhash")
    const raw = calls.find((call) => call.method === "eth_sendRawTransaction").params[0]
    assert.match(raw, /^0x[0-9a-f]+$/)
  })

  test("scripted failures and events drive the session like a real wallet", async () => {
    const win = fakeWindow()
    win.CustomEvent = CustomEvent
    const { provider } = create()
    const stop = installTestProvider(win, provider)
    const session = new WalletSession({ window: win, setTimer: (fn) => { fn(); return 0 }, clearTimer: () => {} })
    session.init({ userId: "1" })
    await tick()
    assert.equal(session.snapshot().wallets[0].name, "FundTogether Test Wallet")

    provider.failNext(4001)
    await assert.rejects(session.connect(), { code: "user_rejected" })
    await session.connect()
    assert.equal(session.address, KEYS.one.address)

    provider.selectAccount(1)
    assert.equal(session.address, KEYS.two.address)
    provider.selectChain(100)
    assert.equal(session.chainId, 100)

    await session.switchChain(normalizeChain({ ...CHAIN_CONFIG, chain_id: 5, rpc_urls: ["https://rpc.invalid/five"] }))
    assert.equal(session.chainId, 5)
    stop()
  })

  test("4902, then add, then switch", async () => {
    const { provider } = create()
    await assert.rejects(provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x64" }] }), { code: 4902 })
    await provider.request({ method: "wallet_addEthereumChain", params: [{ chainId: "0x64", rpcUrls: ["https://rpc.invalid/gnosis"] }] })
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x64" }] })
    assert.equal(await provider.request({ method: "eth_chainId" }), "0x64")
  })
})

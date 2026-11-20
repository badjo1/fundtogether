import "./support/register.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, test } from "node:test"
import { announce, fakeTimers, fakeWindow, providerError } from "./support/mock_provider.mjs"

const { CHAIN_CONFIG, KEYS, SAFE, TOKEN, fakeChain } = await import("./support/fake_chain.js")
const { WalletSession } = await import("wallet/session")
const { normalizeChain } = await import("wallet/chains")
const { decodeFunctionData } = await import("viem")
const { ERC20_ABI, FACTORY_ABI } = await import("safe/abi")
const { FALLBACK_HANDLER, SAFE_L2_SINGLETON, SAFE_PROXY_FACTORY, TOPICS } = await import("safe/constants")
const { verifyDeployedSafe, verifyDeployment } = await import("safe/deploy")
const { contribute, deploySafe, readBalances } = await import("safe/flows")
const { formatAmount, parseAmount } = await import("safe/amounts")
const { createReader, createRpcProvider } = await import("safe/reader")
const { interpretExecution, waitForReceipt } = await import("safe/receipts")

const vectors = JSON.parse(readFileSync(new URL("../fixtures/safe_vectors.json", import.meta.url)))
const real = JSON.parse(readFileSync(new URL("./fixtures/real_receipts.json", import.meta.url)))
const chain = normalizeChain(CHAIN_CONFIG)
const instant = { sleep: async () => {}, timeoutMs: 1000, intervalMs: 0 }

const row = vectors.create2.find((entry) => entry.name.startsWith("fundtogether 2-of-3"))
const PREDICTED = row.predicted_address

function deployment(overrides = {}) {
  return {
    status: "draft",
    chain_id: row.chain_id,
    safe_address: row.predicted_address,
    owners: row.owners,
    threshold: row.threshold,
    salt_nonce: row.salt_nonce,
    initializer: row.initializer,
    factory: row.factory,
    singleton: row.singleton,
    fallback_handler: row.fallback_handler,
    deploy_tx_hash: null,
    ...overrides
  }
}

async function connected(overrides = {}) {
  const fake = fakeChain(overrides)
  const win = fakeWindow()
  const timers = fakeTimers()
  const session = new WalletSession({ window: win, setTimer: timers.setTimer, clearTimer: timers.clearTimer })
  session.init({ userId: "1" })
  announce(win, fake.provider)
  timers.fire(300)
  await session.connect()
  return { session, ...fake }
}

function server(payload) {
  const calls = []
  const record = (verb) => async (url, body) => {
    calls.push({ verb, url, body })
    return payload
  }
  return { calls, get: record("get"), post: record("post"), patch: record("patch") }
}

describe("verifyDeployment", () => {
  const verify = (overrides, options = {}) => verifyDeployment(deployment(overrides), { chainId: row.chain_id, ...options })

  test("an honest deployment passes and yields the factory call", () => {
    const verified = verify()
    assert.equal(verified.safeAddress, PREDICTED)
    const decoded = decodeFunctionData({ abi: FACTORY_ABI, data: verified.data })
    assert.equal(decoded.args[0].toLowerCase(), SAFE_L2_SINGLETON)
    assert.equal(decoded.args[1], row.initializer)
    assert.equal(decoded.args[2].toString(), row.salt_nonce)
  })

  const tampered = [
    ["address", { safe_address: SAFE }, "address_mismatch"],
    ["salt nonce", { salt_nonce: "1" }, "address_mismatch"],
    ["owner swapped", { owners: [KEYS.four.address, row.owners[1], row.owners[2]] }, "initializer_mismatch"],
    ["threshold", { threshold: 1 }, "initializer_mismatch"],
    ["owner order", { owners: [row.owners[1], row.owners[0], row.owners[2]] }, "initializer_mismatch"],
    ["initializer with a setup delegatecall", { initializer: vectors.create2[0].initializer }, "initializer_mismatch"],
    ["factory", { factory: KEYS.one.address }, "deployment_contract_mismatch"],
    ["singleton", { singleton: "0x41675c099f32341bf84bfc5382af534df5c7461a" }, "deployment_contract_mismatch"],
    ["fallback handler", { fallback_handler: KEYS.one.address }, "deployment_contract_mismatch"],
    ["chain", { chain_id: 100 }, "proposal_chain_mismatch"],
    ["duplicate owner", { owners: [row.owners[0], row.owners[0]] }, "deployment_malformed"],
    ["zero owner", { owners: ["0x0000000000000000000000000000000000000000"] }, "deployment_malformed"],
    ["sentinel owner", { owners: ["0x0000000000000000000000000000000000000001"] }, "deployment_malformed"],
    ["no owners", { owners: [] }, "deployment_malformed"],
    ["threshold above owners", { threshold: 4 }, "threshold_out_of_range"],
    ["threshold zero", { threshold: 0 }, "threshold_out_of_range"],
    ["salt as JSON number", { salt_nonce: 5 }, "deployment_malformed"],
    ["malformed initializer", { initializer: "0xzz" }, "deployment_malformed"]
  ]
  for (const [name, overrides, code] of tampered) {
    test(`${name}: ${code}`, () => assert.throws(() => verify(overrides), { code }))
  }

  test("a server that changes the chosen owners or threshold is refused", () => {
    assert.throws(() => verify({}, { intent: { owners: [KEYS.one.address, KEYS.two.address, KEYS.four.address], threshold: 2 } }), { code: "deployment_intent_mismatch" })
    assert.throws(() => verify({}, { intent: { owners: row.owners, threshold: 3 } }), { code: "deployment_intent_mismatch" })
    assert.equal(verify({}, { intent: { owners: [row.owners[2], row.owners[0], row.owners[1]], threshold: 2 } }).safeAddress, PREDICTED)
  })
})

describe("verifyDeployedSafe", () => {
  const expected = { safeAddress: SAFE, owners: [KEYS.one.address, KEYS.two.address], threshold: 2n }
  const live = (overrides = {}) => fakeChain({ owners: expected.owners, threshold: 2n, ...overrides }).provider

  test("a clean Safe passes", async () => {
    await verifyDeployedSafe(createReader(live()), expected)
  })

  const bad = [
    ["no code", { code: new Set() }],
    ["other singleton", { singleton: "0x41675c099f32341bf84bfc5382af534df5c7461a" }],
    ["other owners", { owners: [KEYS.one.address, KEYS.three.address] }],
    ["other threshold", { threshold: 1n }],
    ["a module", { modules: [KEYS.three.address] }],
    ["a guard", { guard: KEYS.three.address }],
    ["other fallback handler", { fallbackHandler: KEYS.three.address }]
  ]
  for (const [name, overrides] of bad) {
    test(name, async () => {
      await assert.rejects(verifyDeployedSafe(createReader(live(overrides)), expected), { code: "deployed_state_mismatch" })
    })
  }
})

describe("deploy flow", () => {
  const urls = { safe: "/accounts/1/safe" }

  function deployState() {
    return {
      owners: row.owners,
      threshold: 2n,
      nonce: 0n,
      code: new Set(),
      simulatedProxy: PREDICTED,
      onSend: null
    }
  }

  const creationLog = { address: SAFE_PROXY_FACTORY, topics: [TOPICS.proxyCreation, `0x${PREDICTED.slice(2).padStart(64, "0")}`], data: "0x" }

  test("sends once to the factory, patches the hash, succeeds only after the receipt and live checks", async () => {
    const { session, state } = await connected(deployState())
    state.onSend = (_tx, hash) => {
      state.code.add(PREDICTED)
      state.receipts.set(hash, { status: "0x1", logs: [creationLog] })
    }
    const http = server(deployment())
    const steps = []
    const result = await deploySafe({ session, http, urls, chain, onStep: (step) => steps.push(step), receiptOptions: instant })
    assert.equal(result.safeAddress, PREDICTED)
    assert.equal(state.sent.length, 1)
    assert.equal(state.sent[0].to, SAFE_PROXY_FACTORY)
    assert.deepEqual(steps, ["preparing", "verifying", "checking_gas", "confirm_in_wallet", "saving", "waiting_receipt", "verifying_deployment"])
    assert.deepEqual(http.calls.map((call) => call.verb), ["get", "patch", "patch"])
    assert.equal(http.calls[1].body.deploy_tx_hash, result.txHash)
  })

  test("createParams post first, and the intent must match the answer", async () => {
    const { session, state } = await connected(deployState())
    const http = server(deployment())
    await assert.rejects(
      deploySafe({
        session, http, urls, chain,
        createParams: { chain_id: row.chain_id, token_address: TOKEN, owners: row.owners, threshold: 3 },
        intent: { owners: row.owners, threshold: 3 },
        receiptOptions: instant
      }),
      { code: "deployment_intent_mismatch" }
    )
    assert.equal(http.calls[0].verb, "post")
    assert.equal(state.sent.length, 0)
  })

  test("a tampered address is refused before the wallet is asked", async () => {
    const { session, state } = await connected(deployState())
    await assert.rejects(deploySafe({ session, http: server(deployment({ safe_address: SAFE })), urls, chain }), { code: "address_mismatch" })
    assert.equal(state.sent.length, 0)
  })

  test("n-of-n without acknowledgement is refused", async () => {
    const { session, state } = await connected(deployState())
    const { buildInitializer, predictSafeAddress } = await import("safe/deploy")
    const initializer = buildInitializer({ owners: row.owners, threshold: 3n })
    const safeAddress = predictSafeAddress({ initializer, saltNonce: BigInt(row.salt_nonce) })
    const payload = deployment({ threshold: 3, initializer, safe_address: safeAddress })
    await assert.rejects(deploySafe({ session, http: server(payload), urls, chain }), { code: "risk_not_acknowledged" })
    assert.equal(state.sent.length, 0)
  })

  test("wrong network: no prompt", async () => {
    const { session, state } = await connected({ ...deployState(), chainId: 100 })
    await assert.rejects(deploySafe({ session, http: server(deployment()), urls, chain }), { code: "wrong_network" })
    assert.equal(state.sent.length, 0)
  })

  test("a simulation that predicts another address refuses", async () => {
    const { session, state } = await connected({ ...deployState(), simulatedProxy: SAFE })
    await assert.rejects(deploySafe({ session, http: server(deployment()), urls, chain }), { code: "address_mismatch" })
    assert.equal(state.sent.length, 0)
  })

  test("front-run with identical calldata: already there, verified, treated as success, nothing sent", async () => {
    const overrides = deployState()
    overrides.code = new Set([PREDICTED])
    const { session, state } = await connected(overrides)
    const http = server(deployment())
    const result = await deploySafe({ session, http, urls, chain, receiptOptions: instant })
    assert.equal(result.safeAddress, PREDICTED)
    assert.equal(state.sent.length, 0)
    assert.deepEqual(http.calls.at(-1), { verb: "patch", url: urls.safe, body: {} })
  })

  test("a retry after the configuration locked reads the existing deployment", async () => {
    const { session, state } = await connected(deployState())
    state.onSend = (_tx, hash) => {
      state.code.add(PREDICTED)
      state.receipts.set(hash, { status: "0x1", logs: [creationLog] })
    }
    const { WalletError } = await import("wallet/errors")
    const http = server(deployment())
    http.post = async () => { throw new WalletError("server_rejected", { details: { status: 422, error: "safe_locked" } }) }
    const result = await deploySafe({ session, http, urls, chain, createParams: { owners: row.owners, threshold: 2 }, receiptOptions: instant })
    assert.equal(result.safeAddress, PREDICTED)
  })

  test("front-run after sending: reverted receipt but the identical Safe exists, so success", async () => {
    const { session, state } = await connected(deployState())
    state.onSend = (_tx, hash) => {
      state.code.add(PREDICTED)
      state.receipts.set(hash, { status: "0x0", logs: [] })
    }
    const result = await deploySafe({ session, http: server(deployment()), urls, chain, receiptOptions: instant })
    assert.equal(result.safeAddress, PREDICTED)
  })

  test("an occupying Safe with other settings is refused", async () => {
    const overrides = deployState()
    overrides.code = new Set([PREDICTED])
    overrides.threshold = 1n
    const { session } = await connected(overrides)
    await assert.rejects(deploySafe({ session, http: server(deployment()), urls, chain }), { code: "deployed_state_mismatch" })
  })

  test("a reverted receipt with no Safe is a failure", async () => {
    const { session, state } = await connected(deployState())
    state.onSend = (_tx, hash) => state.receipts.set(hash, { status: "0x0", logs: [] })
    await assert.rejects(deploySafe({ session, http: server(deployment()), urls, chain, receiptOptions: instant }), { code: "deploy_failed" })
  })

  test("a stored hash is followed instead of sending again", async () => {
    const { session, state } = await connected(deployState())
    const earlier = `0x${"e".repeat(64)}`
    state.transactions.set(earlier, { hash: earlier })
    state.receipts.set(earlier, { status: "0x1", logs: [creationLog] })
    const originalHas = state.code.has.bind(state.code)
    let reads = 0
    state.code.has = (address) => {
      if (address === PREDICTED) {
        reads += 1
        return reads > 1
      }
      return originalHas(address)
    }
    const result = await deploySafe({ session, http: server(deployment({ deploy_tx_hash: earlier })), urls, chain, receiptOptions: instant })
    assert.equal(result.txHash, earlier)
    assert.equal(state.sent.length, 0)
  })

  test("no gas: Dutch message, no prompt", async () => {
    const { session, state } = await connected({ ...deployState(), nativeBalance: 0n })
    await assert.rejects(deploySafe({ session, http: server(deployment()), urls, chain }), { code: "insufficient_gas" })
    assert.equal(state.sent.length, 0)
  })

  test("wallet rejection is neutral and nothing is patched", async () => {
    const { session, provider } = await connected(deployState())
    provider.handlers.eth_sendTransaction = () => { throw providerError(4001) }
    const http = server(deployment())
    await assert.rejects(deploySafe({ session, http, urls, chain }), { code: "user_rejected" })
    assert.deepEqual(http.calls.map((call) => call.verb), ["get"])
  })

  test("uses the canonical fallback handler constant from the vectors", () => {
    assert.equal(FALLBACK_HANDLER, vectors.constants.fallback_handler)
  })
})

describe("amounts", () => {
  const good = [
    ["1", 6, 1000000n],
    ["12,50", 6, 12500000n],
    ["12.50", 6, 12500000n],
    ["0,000001", 6, 1n],
    ["1,500000", 6, 1500000n],
    ["1,5000000", 6, 1500000n],
    ["0.1", 18, 100000000000000000n],
    ["0.3", 18, 300000000000000000n],
    ["1234567890123456789012345678901234567890", 0, 1234567890123456789012345678901234567890n]
  ]
  for (const [input, decimals, units] of good) {
    test(`${input} at ${decimals} decimals`, () => assert.equal(parseAmount(input, decimals), units))
  }

  const bad = [
    ["", "invalid_amount"], ["0", "invalid_amount"], ["0,00", "invalid_amount"], ["-1", "invalid_amount"], ["1e3", "invalid_amount"],
    ["abc", "invalid_amount"], ["1.234,56", "invalid_amount"], ["1,234.56", "invalid_amount"], ["1,2,3", "invalid_amount"], [".5", "invalid_amount"],
    ["0x10", "invalid_amount"], ["1,0000001", "too_many_decimals"]
  ]
  for (const [input, code] of bad) {
    test(`refuses "${input}": ${code}`, () => assert.throws(() => parseAmount(input, 6), { code }))
  }

  test("refuses a JS number outright", () => {
    assert.throws(() => parseAmount(1.5, 6), { code: "invalid_amount" })
    assert.throws(() => parseAmount(1, 6), { code: "invalid_amount" })
  })

  test("refuses above uint256", () => {
    assert.throws(() => parseAmount(`1${"0".repeat(78)}`, 0), { code: "amount_too_large" })
  })

  test("no floating point drift at 18 decimals", () => {
    assert.equal(parseAmount("0.1", 18) + parseAmount("0.2", 18), parseAmount("0.3", 18))
  })

  test("formats in Dutch style without rounding", () => {
    assert.equal(formatAmount(12500000n, 6), "12,50")
    assert.equal(formatAmount(1n, 6), "0,000001")
    assert.equal(formatAmount(1234567000000n, 6), "1.234.567,00")
    assert.equal(formatAmount(0n, 6), "0,00")
    assert.equal(formatAmount(123n, 0), "123")
    assert.equal(formatAmount(10n ** 18n, 18), "1,00")
  })
})

describe("contribute", () => {
  const FROM = KEYS.one.address
  const urls = { sync: "/sync" }
  const transferLog = (hashAmount = 12500000n, to = SAFE) => ({
    address: TOKEN,
    topics: [TOPICS.transfer, `0x${FROM.slice(2).padStart(64, "0")}`, `0x${to.slice(2).padStart(64, "0")}`],
    data: `0x${hashAmount.toString(16).padStart(64, "0")}`
  })

  async function ready(overrides = {}) {
    return connected({ tokenBalances: new Map([[FROM, 100_000_000n]]), ...overrides })
  }

  const args = (session, extra = {}) => ({
    session, http: server({}), urls, chain, tokenAddress: TOKEN, safeAddress: SAFE, amount: "12,50", receiptOptions: instant, ...extra
  })

  test("sends transfer(safe, base units) to the token and confirms from the log", async () => {
    const { session, state } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, { status: "0x1", logs: [transferLog()] })
    const steps = []
    const http = server({})
    const result = await contribute(args(session, { http, onStep: (step) => steps.push(step) }))
    assert.equal(result.units, "12500000")
    assert.equal(result.formatted, "12,50")
    assert.equal(state.sent[0].to, TOKEN)
    const decoded = decodeFunctionData({ abi: ERC20_ABI, data: state.sent[0].data })
    assert.equal(decoded.args[0].toLowerCase(), SAFE)
    assert.equal(decoded.args[1], 12500000n)
    assert.deepEqual(steps, ["checking_balance", "checking_gas", "confirm_in_wallet", "waiting_receipt"])
    assert.deepEqual(http.calls.map((call) => call.url), [urls.sync])
  })

  test("a receipt without a matching transfer is not a success", async () => {
    for (const logs of [[], [transferLog(1n)], [transferLog(12500000n, KEYS.three.address)], [{ ...transferLog(), address: KEYS.three.address }]]) {
      const { session, state } = await ready()
      state.onSend = (_tx, hash) => state.receipts.set(hash, { status: "0x1", logs })
      await assert.rejects(contribute(args(session)), { code: "transfer_unconfirmed" })
    }
  })

  test("a reverted transfer", async () => {
    const { session, state } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, { status: "0x0", logs: [] })
    await assert.rejects(contribute(args(session)), { code: "transfer_reverted" })
  })

  const refused = [
    ["a Safe that is not deployed", { code: new Set() }, {}, "safe_not_deployed"],
    ["too little of the token", { tokenBalances: new Map() }, {}, "insufficient_token"],
    ["chain decimals differ", { tokenDecimals: 18 }, {}, "token_mismatch"],
    ["no gas", { nativeBalance: 0n }, {}, "insufficient_gas"],
    ["wrong network", { chainId: 100 }, {}, "wrong_network"],
    ["a token outside the registry", {}, { tokenAddress: KEYS.three.address }, "token_not_allowed"],
    ["a bad amount", {}, { amount: "1,0000001" }, "too_many_decimals"],
    ["a JS number", {}, { amount: 12.5 }, "invalid_amount"]
  ]
  for (const [name, overrides, extra, code] of refused) {
    test(`${name}: ${code}, no prompt`, async () => {
      const { session, state } = await ready(overrides)
      await assert.rejects(contribute(args(session, extra)), { code })
      assert.equal(state.sent.length, 0)
    })
  }

  test("rejection is neutral", async () => {
    const { session, provider } = await ready()
    provider.handlers.eth_sendTransaction = () => { throw providerError(4001) }
    await assert.rejects(contribute(args(session)), (error) => error.neutral)
  })

  test("balances read from the chain, and an RPC failure is an error, never zero", async () => {
    const { session, state } = await ready({ tokenBalances: new Map([[FROM, 5_000_000n], [SAFE, 42_000_000n]]) })
    const balances = await readBalances({ session, chain, tokenAddress: TOKEN, safeAddress: SAFE })
    assert.equal(balances.fund.formatted, "42,00")
    assert.equal(balances.wallet.units, "5000000")
    assert.equal(balances.gas.symbol, "ETH")
    assert.equal(state.sent.length, 0)

    const broken = await ready()
    broken.provider.handlers.eth_call = () => { throw new Error("rpc down") }
    await assert.rejects(readBalances({ session: broken.session, chain, tokenAddress: TOKEN, safeAddress: SAFE }), { code: "chain_read_failed" })
  })
})

describe("reader and receipts", () => {
  test("RPC provider falls back on HTTP errors but not on a contract revert", async () => {
    const hits = []
    const fetchFn = async (url) => {
      hits.push(url)
      if (url === "https://a") return { ok: false, status: 503 }
      if (url === "https://b") return { ok: true, json: async () => ({ result: "0x1" }) }
      return { ok: true, json: async () => ({ error: { code: 3, message: "execution reverted" } }) }
    }
    const provider = createRpcProvider(["https://a", "https://b"], { fetch: fetchFn })
    assert.equal(await provider.request({ method: "eth_chainId" }), "0x1")
    assert.deepEqual(hits, ["https://a", "https://b"])

    hits.length = 0
    const revert = createRpcProvider(["https://c", "https://b"], { fetch: fetchFn })
    await assert.rejects(revert.request({ method: "eth_call" }), { code: 3 })
    assert.deepEqual(hits, ["https://c"])

    const down = createRpcProvider(["https://a"], { fetch: fetchFn })
    await assert.rejects(down.request({ method: "eth_chainId" }), { code: "chain_read_failed" })
  })

  test("empty eth_call result is a failure, not an empty owner list", async () => {
    const { provider } = fakeChain({ code: new Set() })
    await assert.rejects(createReader(provider).owners(SAFE), { code: "chain_read_failed" })
  })

  test("polling survives an RPC hiccup, and times out as pending, not failed", async () => {
    let calls = 0
    const reader = { receipt: async () => {
      calls += 1
      if (calls === 1) throw new Error("hiccup")
      return calls === 2 ? null : { status: "0x1" }
    } }
    assert.deepEqual(await waitForReceipt(reader, "0x1", instant), { status: "0x1" })

    let clock = 0
    await assert.rejects(
      waitForReceipt({ receipt: async () => null }, "0x1", { sleep: async () => { clock += 100 }, timeoutMs: 200, intervalMs: 0, now: () => clock }),
      { code: "receipt_timeout" }
    )
  })

  for (const row2 of vectors.safe_tx_hashes.filter((entry) => entry.tx_hash)) {
    test(`real receipt of ${row2.name} reads as success`, () => {
      const receipt = real.txs[row2.tx_hash]
      assert.equal(interpretExecution({ status: receipt.status, logs: receipt.logs }, { safe: row2.safe, safeTxHash: row2.safe_tx_hash }), "success")
      assert.equal(interpretExecution({ status: receipt.status, logs: receipt.logs }, { safe: row2.safe, safeTxHash: `0x${"00".repeat(32)}` }), "unconfirmed")
      assert.equal(interpretExecution({ status: "0x0", logs: receipt.logs }, { safe: row2.safe, safeTxHash: row2.safe_tx_hash }), "reverted")
    })
  }

  test("real ProxyCreation logs give the predicted address", async () => {
    const { proxyCreatedAt } = await import("safe/receipts")
    for (const entry of vectors.create2.filter((item) => item.tx_hash)) {
      const receipt = real.txs[entry.tx_hash]
      assert.equal(proxyCreatedAt(receipt, { factory: entry.factory, proxy: entry.predicted_address }), true, entry.name)
      assert.equal(proxyCreatedAt(receipt, { factory: entry.factory, proxy: SAFE }), false, entry.name)
    }
  })
})

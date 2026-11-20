// Stage F, docs/SECURITY_REVIEW.md: M1 (contribute verifies the destination), M5 (link message), M6 (title text),
// M11 (execution knows about the balance), L4 (ambiguous amounts).
import "./support/register.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, test } from "node:test"
import { announce, fakeTimers, fakeWindow } from "./support/mock_provider.mjs"

const { CHAIN_CONFIG, KEYS, SAFE, TOKEN, fakeChain } = await import("./support/fake_chain.js")
const { WalletSession } = await import("wallet/session")
const { normalizeChain } = await import("wallet/chains")
const { linkWallet } = await import("wallet/link")
const { formatAmount, parseAmount, echoAmount } = await import("safe/amounts")
const { contribute, verifyFundSafe, executionReadiness, executeProposal } = await import("safe/flows")
const { createReader } = await import("safe/reader")
const { cleanText } = await import("safe/values")
const { encodeFunctionData } = await import("viem")
const { ERC20_ABI } = await import("safe/abi")

const chain = normalizeChain(CHAIN_CONFIG)
const instant = { sleep: async () => {}, timeoutMs: 1000, intervalMs: 0 }
const vectors = JSON.parse(readFileSync(new URL("../fixtures/safe_vectors.json", import.meta.url)))
const row = vectors.create2.find((entry) => entry.name.startsWith("fundtogether 2-of-3"))

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

describe("L4: amounts", () => {
  for (const text of ["1.000", "12.500", "999.999", "1.000.000"]) {
    test(`refuses ${text} as ambiguous`, () => assert.throws(() => parseAmount(text, 6), { code: "ambiguous_amount" }))
  }
  for (const [text, units] of [["0.001", 1000n], ["0.75", 750000n], ["1.5", 1500000n], ["1,000", 1000000n], ["1.0000", 1000000n], ["1000", 1000000000n]]) {
    test(`${text} stays allowed`, () => assert.equal(parseAmount(text, 6), units))
  }
  test("the echo shows how an amount is read, or why it is not", () => {
    assert.deepEqual(echoAmount("1,5", { decimals: 6, symbol: "EURC" }), { ok: true, text: "Dat is precies 1,50 EURC." })
    assert.deepEqual(echoAmount("1234,5", { decimals: 6, symbol: "EURC" }), { ok: true, text: "Dat is precies 1.234,50 EURC." })
    assert.equal(echoAmount("1.000", { decimals: 6, symbol: "EURC" }).ok, false)
    assert.match(echoAmount("1.000", { decimals: 6, symbol: "EURC" }).text, /Bedoel je/)
    assert.deepEqual(echoAmount("", { decimals: 6, symbol: "EURC" }), { ok: false, text: "" })
  })
  test("Ruby and JS agree on what is ambiguous", () => {
    const source = readFileSync(new URL("../../app/services/chain/amount.rb", import.meta.url), "utf8")
    assert.ok(source.includes("AMBIGUOUS_FORMAT = /\\A[1-9][0-9]{0,2}(\\.[0-9]{3})+\\z/"), "same pattern as safe/amounts.js")
    assert.equal(formatAmount(1000000n, 6), "1,00")
  })
})

describe("M1: the destination of a contribution is checked on-chain", () => {
  const verify = (overrides = {}, extra = {}) => {
    const fake = fakeChain({ owners: [KEYS.one.address, KEYS.two.address], threshold: 2n, ...overrides })
    return verifyFundSafe({ reader: createReader(fake.provider), chain, safeAddress: SAFE, ...extra })
  }

  test("a canonical Safe gives owners and threshold from the chain, checksummed", async () => {
    const result = await verify()
    assert.equal(result.threshold, "2")
    assert.equal(result.owners.length, 2)
    assert.ok(result.owners.every((owner) => /[A-F]/.test(owner)), "checksummed")
    assert.match(result.address, /^0x/)
  })

  for (const [name, overrides, code] of [
    ["a look-alike singleton", { singleton: "0x9999999999999999999999999999999999999999" }, "safe_not_canonical"],
    ["a guard", { guard: "0x9999999999999999999999999999999999999999" }, "safe_has_guard"],
    ["a module", { modules: ["0x9999999999999999999999999999999999999999"] }, "safe_has_modules"],
    ["another fallback handler", { fallbackHandler: "0x9999999999999999999999999999999999999999" }, "safe_bad_fallback"]
  ]) {
    test(`refuses ${name}`, async () => assert.rejects(verify(overrides), { code }))
  }

  test("refuses when the address does not follow from the deployment the server gives", async () => {
    const deployment = { chain_id: chain.chainId, safe_address: row.predicted_address, owners: row.owners, threshold: row.threshold, salt_nonce: row.salt_nonce,
                         initializer: row.initializer, factory: row.factory, singleton: row.singleton, fallback_handler: row.fallback_handler }
    await assert.rejects(verify({}, { deployment, safeAddress: SAFE }), { code: "address_mismatch" })
    const matching = await verifyFundSafe({ reader: createReader(fakeChain({ owners: [KEYS.one.address], threshold: 1n, code: new Set([row.predicted_address]) }).provider), chain, safeAddress: row.predicted_address, deployment })
    assert.equal(matching.owners.length, 1)
  })

  test("contribute refuses before any wallet prompt when the Safe fails", async () => {
    const FROM = KEYS.one.address
    const { session, state } = await connected({ tokenBalances: new Map([[FROM, 100_000_000n]]), singleton: "0x9999999999999999999999999999999999999999" })
    const sent = []
    state.onSend = (tx) => sent.push(tx)
    const http = { get: async () => { throw new Error("not used") }, post: async () => ({}) }
    await assert.rejects(contribute({ session, http, urls: { sync: "/sync" }, chain, tokenAddress: TOKEN, safeAddress: SAFE, amount: "1", receiptOptions: instant }), { code: "safe_not_canonical" })
    assert.equal(sent.length, 0)
  })

  test("contribute asks the server for the deployment when given a url, and refuses a mismatch", async () => {
    const FROM = KEYS.one.address
    const { session } = await connected({ tokenBalances: new Map([[FROM, 100_000_000n]]) })
    const deployment = { chain_id: 11155111, safe_address: row.predicted_address, owners: row.owners, threshold: row.threshold, salt_nonce: row.salt_nonce,
                         initializer: row.initializer, factory: row.factory, singleton: row.singleton, fallback_handler: row.fallback_handler }
    const http = { get: async () => deployment, post: async () => ({}) }
    await assert.rejects(contribute({ session, http, urls: { sync: "/sync", safe: "/safe" }, chain, tokenAddress: TOKEN, safeAddress: SAFE, amount: "1", receiptOptions: instant }), { code: "address_mismatch" })
  })
})

describe("M5: the link message", () => {
  const address = KEYS.one.address
  const message = (domain) => `${domain} wants you to sign in with your Ethereum account:\n${address}\n\nKoppel deze wallet. Account: a@example.com\n\nNonce: abc123`

  async function run(domain, host) {
    const fake = await connected()
    globalThis.location = { host }
    try {
      const http = { post: async (url) => url === "/c" ? { nonce: "abc123", message: message(domain) } : { id: 1, address } }
      return await linkWallet({ session: fake.session, http, urls: { challenges: "/c", wallets: "/w" } })
    } finally {
      delete globalThis.location
    }
  }

  test("a message for another domain is refused before signing", async () => {
    await assert.rejects(run("evil.test", "fundtogether.test"), { code: "challenge_mismatch" })
  })
  test("a message for this domain is signed", async () => {
    assert.equal((await run("fundtogether.test", "fundtogether.test")).address, address)
  })
})

describe("M6: server text on the review", () => {
  test("bidi and invisible characters are removed from the title", () => {
    assert.equal(cleanText("Naar‮ Bob​\u0000"), "Naar Bob")
    assert.equal(cleanText(undefined), "")
  })
})

describe("M11: execution knows about the balance", () => {
  const RECIPIENT = KEYS.four.address
  const data = encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [RECIPIENT, 1000000n] })
  const proposal = () => ({
    id: 1, kind: "transfer_token", title: "T", params: { recipient: RECIPIENT, amount: "1000000" }, state: "open", chain_id: 11155111, safe_address: SAFE,
    to: TOKEN, value: "0", data, operation: 0, safe_tx_gas: "0", base_gas: "0", gas_price: "0", gas_token: "0x0000000000000000000000000000000000000000",
    refund_receiver: "0x0000000000000000000000000000000000000000", nonce: "5", token: { address: TOKEN, symbol: "EURC", decimals: 6 }, signatures: []
  })

  test("readiness says not ready when the fund cannot pay, and execute refuses without a prompt", async () => {
    const { session, state } = await connected({ owners: [KEYS.one.address], threshold: 1n, nonce: 5n, tokenBalances: new Map([[SAFE, 5n]]) })
    const { safeTxHash } = await import("safe/hash")
    const { privateKeyToAccount } = await import("./support/vendor/viem_accounts.js")
    const body = proposal()
    const tx = { to: TOKEN, value: 0n, data, operation: 0, safeTxGas: 0n, baseGas: 0n, gasPrice: 0n, gasToken: "0x0000000000000000000000000000000000000000", refundReceiver: "0x0000000000000000000000000000000000000000", nonce: 5n }
    const hash = safeTxHash({ chainId: 11155111, safe: SAFE, tx })
    body.safe_tx_hash = hash
    const signature = await privateKeyToAccount(KEYS.one.key).sign({ hash })
    body.signatures = [{ signer: KEYS.one.address, signature }]
    const http = { get: async () => body, post: async () => body }
    const args = { session, http, urls: { proposal: "/p", execution: "/e", sync: "/s" }, chain, safeAddress: SAFE, receiptOptions: instant }
    const readiness = await executionReadiness(args)
    assert.equal(readiness.ready, false)
    assert.equal(readiness.sufficient, false)
    const sent = []
    state.onSend = (sentTx) => sent.push(sentTx)
    await assert.rejects(executeProposal(args), { code: "insufficient_fund_balance" })
    assert.equal(sent.length, 0)
  })
})

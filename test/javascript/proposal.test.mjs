import "./support/register.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, test } from "node:test"
import { announce, deferred, fakeTimers, fakeWindow, providerError, tick } from "./support/mock_provider.mjs"

const { CHAIN_CONFIG, KEYS, SAFE, TOKEN, executionReceipt, fakeChain, signProposalHash } = await import("./support/fake_chain.js")
const { WalletSession } = await import("wallet/session")
const { normalizeChain } = await import("wallet/chains")
const { encodeFunctionData } = await import("viem")
const { ERC20_ABI, SAFE_ABI } = await import("safe/abi")
const { SENTINEL_OWNERS, TOPICS, ZERO_ADDRESS } = await import("safe/constants")
const { safeTxHash, typedDataPayload } = await import("safe/hash")
const { executeProposal, executionReadiness, reviewProposal, signProposal } = await import("safe/flows")
const { createReader } = await import("safe/reader")
const { verifyProposal } = await import("safe/verify")
const { encodeSignatures, recoverSigner } = await import("safe/signatures")

const vectors = JSON.parse(readFileSync(new URL("../fixtures/safe_vectors.json", import.meta.url)))
const chain = normalizeChain(CHAIN_CONFIG)
const RECIPIENT = KEYS.four.address
const instant = { sleep: async () => {}, timeoutMs: 1000, intervalMs: 0 }

function txFields(overrides) {
  return {
    to: TOKEN,
    value: 0n,
    data: "0x",
    operation: 0,
    safeTxGas: 0n,
    baseGas: 0n,
    gasPrice: 0n,
    gasToken: ZERO_ADDRESS,
    refundReceiver: ZERO_ADDRESS,
    nonce: 5n,
    ...overrides
  }
}

function makeProposal({ kind = "transfer_token", params, to, value = 0n, data, nonce = 5n, ...rest } = {}) {
  const resolved = {
    params: params ?? { recipient: RECIPIENT, amount: "1000000" },
    to: to ?? TOKEN,
    data: data ?? encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [RECIPIENT, 1000000n] })
  }
  const tx = txFields({ to: resolved.to, value, data: resolved.data, nonce })
  return {
    id: 1,
    kind,
    title: "Test",
    params: resolved.params,
    state: "open",
    chain_id: 11155111,
    safe_address: SAFE,
    to: resolved.to,
    value: value.toString(),
    data: resolved.data,
    operation: 0,
    safe_tx_gas: "0",
    base_gas: "0",
    gas_price: "0",
    gas_token: ZERO_ADDRESS,
    refund_receiver: ZERO_ADDRESS,
    nonce: nonce.toString(),
    safe_tx_hash: safeTxHash({ chainId: 11155111, safe: SAFE, tx }),
    token: { address: TOKEN, symbol: "EURC", decimals: 6 },
    signatures: [],
    execution_tx_hash: null,
    ...rest
  }
}

function server(proposal, posted = []) {
  return {
    posted,
    get: async () => proposal,
    post: async (url, body) => {
      posted.push({ url, body })
      return proposal
    }
  }
}

const urls = { proposal: "/p/1", signatures: "/p/1/signatures", execution: "/p/1/execution", sync: "/sync" }

async function connectedSession(overrides = {}) {
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

async function signaturesFor(proposal, keys) {
  const typed = JSON.parse(typedDataPayload({
    chainId: 11155111,
    safe: SAFE,
    tx: txFields({ to: proposal.to, value: BigInt(proposal.value), data: proposal.data, nonce: BigInt(proposal.nonce) })
  }))
  return Promise.all(keys.map(async (entry) => ({ signer: entry.address, signature: await signProposalHash(entry.key, typed) })))
}

function verify(proposal, overrides) {
  const { provider } = fakeChain(overrides)
  return verifyProposal({ proposal, reader: createReader(provider), chain, safeAddress: SAFE })
}

describe("verification: everything the server can tamper with", () => {
  test("an honest proposal passes and decodes", async () => {
    const { display, hash } = await verify(makeProposal())
    assert.equal(hash, makeProposal().safe_tx_hash)
    assert.match(display.summary, /^Stuur 1,00 EURC naar 0x1efF47bc3a10a45D4B230B5d10E37751FE6AA718$/)
    assert.equal(display.operation, "CALL")
    assert.equal(display.threshold, "2")
    assert.equal(display.safeTxHash, hash)
    assert.match(display.domainHash, /^0x[0-9a-f]{64}$/)
    assert.match(display.messageHash, /^0x[0-9a-f]{64}$/)
  })

  const tampers = [
    ["hash differs", { safe_tx_hash: `0x${"ab".repeat(32)}` }, "hash_mismatch"],
    ["data swaps the recipient", { data: encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [KEYS.three.address, 1000000n] }) }, "calldata_mismatch"],
    ["data raises the amount", { data: encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [RECIPIENT, 9000000n] }) }, "calldata_mismatch"],
    ["params differ from data", { params: { recipient: RECIPIENT, amount: "5" } }, "calldata_mismatch"],
    ["to is another token", { to: KEYS.three.address }, "unknown_target_data"],
    ["delegatecall", { operation: 1 }, "operation_not_call"],
    ["safeTxGas", { safe_tx_gas: "1" }, "safe_tx_gas_nonzero"],
    ["baseGas", { base_gas: "1" }, "base_gas_nonzero"],
    ["gasPrice", { gas_price: "1" }, "gas_price_nonzero"],
    ["gasToken", { gas_token: TOKEN }, "gas_token_nonzero"],
    ["refundReceiver", { refund_receiver: RECIPIENT }, "refund_receiver_nonzero"],
    ["wrong chain", { chain_id: 100 }, "proposal_chain_mismatch"],
    ["other Safe", { safe_address: KEYS.three.address }, "proposal_safe_mismatch"],
    ["unknown token", { token: { address: KEYS.three.address, symbol: "EURC", decimals: 6 } }, "token_not_allowed"],
    ["decimals lie", { token: { address: TOKEN, symbol: "EURC", decimals: 18 } }, "token_mismatch"],
    ["closed", { state: "executed" }, "proposal_closed"],
    ["superseded", { state: "superseded" }, "proposal_closed"],
    ["unknown kind", { kind: "exec_raw" }, "unknown_kind"],
    ["smuggled prev_owner", { params: { recipient: RECIPIENT, amount: "1000000", prev_owner: SENTINEL_OWNERS } }, "unexpected_param"],
    ["amount as JSON number", { params: { recipient: RECIPIENT, amount: 1000000 } }, "invalid_amount"],
    ["nonce as JSON number", { nonce: 5 }, "invalid_nonce"],
    ["malformed hash", { safe_tx_hash: "0x12" }, "proposal_malformed"]
  ]
  for (const [name, change, code] of tampers) {
    test(`${name}: ${code}`, async () => {
      await assert.rejects(verify({ ...makeProposal(), ...change }), { code })
    })
  }

  test("nonce below the Safe's: nonce_too_low", async () => {
    await assert.rejects(verify(makeProposal({ nonce: 4n })), { code: "nonce_too_low" })
  })

  test("the on-chain getTransactionHash disagrees: chain_hash_mismatch", async () => {
    await assert.rejects(verify(makeProposal(), { onChainHash: `0x${"cd".repeat(32)}` }), { code: "chain_hash_mismatch" })
  })

  test("a non-canonical singleton: safe_not_canonical", async () => {
    await assert.rejects(verify(makeProposal(), { singleton: KEYS.three.address }), { code: "safe_not_canonical" })
  })

  test("reads on the wrong chain: chain_read_mismatch", async () => {
    await assert.rejects(verify(makeProposal(), { chainId: 100 }), { code: "chain_read_mismatch" })
  })

  test("token decimals differ on chain: token_mismatch", async () => {
    await assert.rejects(verify(makeProposal(), { tokenDecimals: 18 }), { code: "token_mismatch" })
  })

  test("no code at the Safe address: chain_read_failed, not a pass", async () => {
    await assert.rejects(verify(makeProposal(), { code: new Set() }), { code: "chain_read_failed" })
  })

  for (const selector of ["enableModule", "setGuard"]) {
    test(`a ${selector} self-call is refused even with a matching hash`, async () => {
      const data = selector === "enableModule"
        ? `0x610b5925${KEYS.four.address.slice(2).padStart(64, "0")}`
        : `0xe19a9dd9${KEYS.four.address.slice(2).padStart(64, "0")}`
      const proposal = makeProposal({ kind: "add_owner", to: SAFE, data, params: { owner: KEYS.four.address, threshold: 2 } })
      await assert.rejects(verify(proposal), { code: "self_call_forbidden" })
    })
  }

  test("prevOwner comes from live owners, and a changed owner list refuses", async () => {
    const data = encodeFunctionData({ abi: SAFE_ABI, functionName: "removeOwner", args: [KEYS.one.address, KEYS.two.address, 1n] })
    const proposal = makeProposal({ kind: "remove_owner", to: SAFE, data, params: { owner: KEYS.two.address, threshold: 1 } })
    await verify(proposal)
    await assert.rejects(verify(proposal, { owners: [KEYS.three.address, KEYS.two.address, KEYS.one.address] }), { code: "calldata_mismatch" })
    await assert.rejects(verify(proposal, { owners: [KEYS.one.address, KEYS.three.address] }), { code: "owner_unknown" })
  })

  test("a rejection decodes and must target its own nonce", async () => {
    const proposal = makeProposal({ kind: "rejection", to: SAFE, data: "0x", params: { nonce: "5" }, token: null })
    const { display } = await verify(proposal)
    assert.match(display.summary, /Wijs het voorstel met nonce 5 af/)
    await assert.rejects(verify({ ...proposal, params: { nonce: "6" } }), { code: "invalid_nonce" })
  })

  test("all owner kinds rebuild from the shared vectors, against live owners", async () => {
    for (const row of vectors.calldata.filter((entry) => entry.context.safe === SAFE)) {
      const { expected, context } = row
      const proposal = {
        ...makeProposal({ kind: row.kind, params: row.params, to: expected.to, value: BigInt(expected.value), data: expected.data, nonce: BigInt(row.nonce) }),
        safe_tx_hash: expected.safe_tx_hash
      }
      const { display } = await verify(proposal, { owners: context.owners, threshold: BigInt(context.threshold), nonce: BigInt(context.current_nonce) })
      assert.ok(display.summary.length > 0, row.name)
    }
  })

  test("signatures from non-owners and duplicates do not count", async () => {
    const proposal = makeProposal()
    const good = await signaturesFor(proposal, [KEYS.one, KEYS.two])
    const stranger = await signaturesFor(proposal, [KEYS.four])
    const { valid, rejected } = await verify({ ...proposal, signatures: [...good, good[0], ...stranger, { signer: KEYS.three.address, signature: "0x1234" }] })
    assert.deepEqual(valid.map((entry) => entry.signer), [KEYS.two.address, KEYS.one.address])
    assert.deepEqual(rejected.map((entry) => entry.reason), ["not_owner", "invalid"])
  })
})

describe("review and sign flow", () => {
  const signArgs = (session, proposal, posted) => ({
    session,
    http: server(proposal, posted),
    urls,
    chain,
    safeAddress: SAFE,
    linked: [KEYS.one.address]
  })

  test("signs typed data from local fields and posts a signature that recovers", async () => {
    const { session, state } = await connectedSession()
    const proposal = makeProposal()
    const posted = []
    const steps = []
    const result = await signProposal({ ...signArgs(session, proposal, posted), reviewedHash: proposal.safe_tx_hash, onStep: (step) => steps.push(step) })
    assert.deepEqual(steps, ["loading", "verifying", "sign_typed_data", "saving_signature"])
    assert.equal(result.signer, KEYS.one.address)
    assert.equal(posted.length, 1)
    assert.equal(posted[0].url, urls.signatures)
    assert.equal(await recoverSigner(proposal.safe_tx_hash, posted[0].body.signature), KEYS.one.address)
    const { typed } = state.signed[0]
    assert.deepEqual(typed.domain, { chainId: 11155111, verifyingContract: SAFE })
    assert.equal(typed.primaryType, "SafeTx")
    assert.equal(typed.message.nonce, "5")
    assert.equal(session.state, "connected")
  })

  test("review works without a wallet through the RPC, and signs nothing", async () => {
    const fake = fakeChain()
    const timers = fakeTimers()
    const session = new WalletSession({ window: fakeWindow(), setTimer: timers.setTimer, clearTimer: timers.clearTimer })
    const originalFetch = globalThis.fetch
    globalThis.fetch = async (_url, options) => {
      const { method, params, id } = JSON.parse(options.body)
      const result = await fake.provider.request({ method, params })
      return { ok: true, json: async () => ({ jsonrpc: "2.0", id, result }) }
    }
    try {
      const { display } = await reviewProposal({ session, http: server(makeProposal()), urls, chain, safeAddress: SAFE })
      assert.match(display.summary, /Stuur 1,00 EURC/)
      assert.equal(fake.state.signed.length, 0)
    } finally {
      globalThis.fetch = originalFetch
    }
  })

  test("a mismatched server hash never reaches the wallet", async () => {
    const { session, state } = await connectedSession()
    const proposal = { ...makeProposal(), safe_tx_hash: `0x${"ab".repeat(32)}` }
    const posted = []
    await assert.rejects(signProposal(signArgs(session, proposal, posted)), { code: "hash_mismatch" })
    assert.equal(state.signed.length, 0)
    assert.equal(posted.length, 0)
  })

  test("a proposal that changed since review is refused", async () => {
    const { session, state } = await connectedSession()
    const posted = []
    await assert.rejects(
      signProposal({ ...signArgs(session, makeProposal(), posted), reviewedHash: `0x${"ee".repeat(32)}` }),
      { code: "review_outdated" }
    )
    assert.equal(state.signed.length, 0)
  })

  test("wrong chain: no prompt", async () => {
    const { session, state, provider } = await connectedSession()
    provider.handlers.eth_chainId = () => "0x64"
    await assert.rejects(signProposal(signArgs(session, makeProposal(), [])), { code: "wrong_network" })
    assert.equal(state.signed.length, 0)
  })

  test("an unlinked address: no prompt", async () => {
    const { session, state } = await connectedSession({ active: KEYS.two })
    await assert.rejects(signProposal(signArgs(session, makeProposal(), [])), { code: "address_not_linked" })
    assert.equal(state.signed.length, 0)
  })

  test("a linked address that is not an owner: no prompt", async () => {
    const { session, state } = await connectedSession({ active: KEYS.four })
    await assert.rejects(signProposal({ ...signArgs(session, makeProposal(), []), linked: [KEYS.four.address] }), { code: "not_owner" })
    assert.equal(state.signed.length, 0)
  })

  test("already signed: no second prompt", async () => {
    const { session, state } = await connectedSession()
    const proposal = makeProposal()
    proposal.signatures = await signaturesFor(proposal, [KEYS.one])
    await assert.rejects(signProposal(signArgs(session, proposal, [])), (error) => error.code === "already_signed")
    assert.equal(state.signed.length, 0)
  })

  test("rejecting in the wallet posts nothing", async () => {
    const { session, provider } = await connectedSession()
    provider.handlers.eth_signTypedData_v4 = () => { throw providerError(4001) }
    const posted = []
    await assert.rejects(signProposal(signArgs(session, makeProposal(), posted)), { code: "user_rejected" })
    assert.equal(posted.length, 0)
    assert.equal(session.state, "connected")
  })

  test("account switched mid-signature posts nothing, even if the wallet answers later", async () => {
    const { session, provider } = await connectedSession()
    const pending = deferred()
    provider.handlers.eth_signTypedData_v4 = () => pending.promise
    const posted = []
    const attempt = signProposal(signArgs(session, makeProposal(), posted))
    while (session.state !== "awaiting_signature") await tick()
    provider.emit("accountsChanged", [KEYS.two.address])
    await assert.rejects(attempt, { code: "stale" })
    pending.resolve(`0x${"11".repeat(65)}`)
    await tick()
    assert.equal(posted.length, 0)
    assert.equal(session.state, "stale")
  })

  test("a wallet returning another key's signature posts nothing", async () => {
    const { session, state } = await connectedSession()
    state.signatureOverride = (typed) => signProposalHash(KEYS.two.key, typed)
    const posted = []
    await assert.rejects(signProposal(signArgs(session, makeProposal(), posted)), { code: "signature_mismatch" })
    assert.equal(posted.length, 0)
    assert.equal(session.state, "connected")
  })

  test("v 0/1 from a hardware path is normalised before posting", async () => {
    const { session, state } = await connectedSession()
    state.signatureOverride = async (typed) => {
      const signature = await signProposalHash(KEYS.one.key, typed)
      return `${signature.slice(0, 130)}${(parseInt(signature.slice(130), 16) - 27).toString(16).padStart(2, "0")}`
    }
    const posted = []
    await signProposal(signArgs(session, makeProposal(), posted))
    assert.ok(["1b", "1c"].includes(posted[0].body.signature.slice(130)))
  })

  test("a garbage signature posts nothing", async () => {
    const { session, state } = await connectedSession()
    state.signatureOverride = () => "0x1234"
    const posted = []
    await assert.rejects(signProposal(signArgs(session, makeProposal(), posted)), { code: "invalid_signature_format" })
    assert.equal(posted.length, 0)
  })
})

describe("execution flow", () => {
  async function ready(overrides = {}, proposalOverrides = {}) {
    const fake = await connectedSession(overrides)
    const proposal = { ...makeProposal(), ...proposalOverrides }
    if (!proposalOverrides.signatures) proposal.signatures = await signaturesFor(proposal, [KEYS.one, KEYS.two])
    return { ...fake, proposal }
  }

  const args = (session, proposal, posted = []) => ({ session, http: server(proposal, posted), urls, chain, safeAddress: SAFE, receiptOptions: instant })

  test("signatures go in ascending numeric owner order, exactly threshold of them", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    proposal.signatures = await signaturesFor(proposal, [KEYS.one, KEYS.two, KEYS.three])
    const result = await executeProposal(args(session, proposal))
    assert.equal(result.outcome, "success")

    const { decodeFunctionData } = await import("viem")
    const decoded = decodeFunctionData({ abi: SAFE_ABI, data: state.sent[0].data })
    assert.equal(decoded.functionName, "execTransaction")
    const signatures = decoded.args[9]
    assert.equal((signatures.length - 2) / 130, 2)
    const signers = [
      await recoverSigner(proposal.safe_tx_hash, `0x${signatures.slice(2, 132)}`),
      await recoverSigner(proposal.safe_tx_hash, `0x${signatures.slice(132, 262)}`)
    ]
    // Lowest two of 0x2b5a, 0x6813, 0x7e5f.
    assert.deepEqual(signers, [KEYS.two.address, KEYS.three.address])
    assert.equal(state.sent[0].to, SAFE)
    assert.equal(state.sent[0].value, "0x0")
    assert.equal(state.sent[0].from, KEYS.one.address)
    assert.equal(state.sent[0].gas, "0x1fbd0")
  })

  // Found live on Sepolia: the page reloaded on "executed" while the only post-receipt hint was the background sync,
  // so the proposal still read as open until someone refreshed.
  test("the execution endpoint hears about the mined transaction before the flow reports success", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => { state.pendingHash = hash }
    const calls = []
    const http = {
      get: async () => proposal,
      post: async (url, body) => {
        calls.push({ url, body, mined: state.receipts.has(body.tx_hash) })
        if (url === urls.execution && !state.receipts.has(body.tx_hash)) state.receipts.set(body.tx_hash, executionReceipt({ hash: proposal.safe_tx_hash }))
        return proposal
      }
    }
    await executeProposal({ session, http, urls, chain, safeAddress: SAFE, receiptOptions: instant })
    const executions = calls.filter((call) => call.url === urls.execution)
    assert.equal(executions.length, 2)
    assert.equal(executions[0].mined, false)
    assert.equal(executions[1].mined, true)
    assert.equal(executions[1].body.tx_hash, state.pendingHash)
  })

  test("nothing is a success before the receipt: steps stop at waiting_receipt until it arrives", async () => {
    const { session, state, proposal } = await ready()
    let hash = null
    state.onSend = (_tx, sent) => { hash = sent }
    const steps = []
    const posted = []
    let settled = false
    const release = deferred()
    const attempt = executeProposal({
      ...args(session, proposal, posted),
      onStep: (step) => steps.push(step),
      receiptOptions: { intervalMs: 0, timeoutMs: 60_000, sleep: () => release.promise }
    }).then((result) => { settled = true; return result })
    while (!steps.includes("waiting_receipt") || state.sent.length === 0) await tick()
    await tick()
    assert.equal(settled, false)
    state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    release.resolve()
    const result = await attempt
    assert.equal(result.outcome, "success")
    assert.deepEqual(steps, ["loading", "verifying", "checking_gas", "confirm_in_wallet", "saving", "waiting_receipt"])
    assert.deepEqual(posted.map((entry) => entry.url), [urls.execution, urls.execution, urls.sync])
  })

  test("ExecutionFailure with status 1 is not success", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash, topic: TOPICS.executionFailure }))
    await assert.rejects(executeProposal(args(session, proposal)), { code: "execution_failed" })
  })

  test("status 0 reverted", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash, status: "0x0" }))
    await assert.rejects(executeProposal(args(session, proposal)), { code: "execution_reverted" })
  })

  test("status 1 without the event is not success", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, { status: "0x1", logs: [] })
    await assert.rejects(executeProposal(args(session, proposal)), { code: "execution_unconfirmed" })
  })

  test("ExecutionSuccess for another hash or from another contract is not success", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: `0x${"99".repeat(32)}` }))
    await assert.rejects(executeProposal(args(session, proposal)), { code: "execution_unconfirmed" })

    const second = await ready()
    second.state.onSend = (_tx, hash) => second.state.receipts.set(hash, executionReceipt({ hash: second.proposal.safe_tx_hash, safe: TOKEN }))
    await assert.rejects(executeProposal(args(second.session, second.proposal)), { code: "execution_unconfirmed" })
  })

  test("too few valid signatures: nothing sent", async () => {
    const { session, state, proposal } = await ready({}, { signatures: [] })
    proposal.signatures = await signaturesFor(proposal, [KEYS.one])
    await assert.rejects(executeProposal(args(session, proposal)), { code: "not_enough_signatures" })
    assert.equal(state.sent.length, 0)
  })

  test("signatures from removed owners do not count", async () => {
    const { session, state, proposal } = await ready({ owners: [KEYS.one.address, KEYS.three.address] })
    await assert.rejects(executeProposal(args(session, proposal)), { code: "not_enough_signatures" })
    assert.equal(state.sent.length, 0)
  })

  test("a raised threshold is read live, not from the server", async () => {
    const { session, state, proposal } = await ready({ threshold: 3n })
    await assert.rejects(executeProposal(args(session, proposal)), { code: "not_enough_signatures" })
    assert.equal(state.sent.length, 0)
  })

  test("a queued nonce cannot run yet", async () => {
    const fake = await connectedSession()
    const proposal = makeProposal({ nonce: 6n })
    proposal.signatures = await signaturesFor(proposal, [KEYS.one, KEYS.two])
    await assert.rejects(executeProposal(args(fake.session, proposal)), { code: "nonce_not_current" })
    assert.equal(fake.state.sent.length, 0)
  })

  test("no gas at all gives the Dutch gas message and no prompt", async () => {
    const { session, state, proposal } = await ready({ nativeBalance: 0n })
    await assert.rejects(executeProposal(args(session, proposal)), (error) => {
      assert.equal(error.code, "insufficient_gas")
      assert.match(error.message, /te weinig tegoed/)
      assert.match(error.message, /ETH op Sepolia/)
      return true
    })
    assert.equal(state.sent.length, 0)
  })

  test("too little gas names the estimate", async () => {
    const { session, state, proposal } = await ready({ nativeBalance: 1000n })
    await assert.rejects(executeProposal(args(session, proposal)), (error) => {
      assert.equal(error.code, "insufficient_gas")
      assert.match(error.message, /Schatting: 0,00013 ETH/)
      return true
    })
    assert.equal(state.sent.length, 0)
  })

  test("a simulated revert is translated and nothing is sent", async () => {
    const { session, state, proposal } = await ready({ estimateError: providerError(3, "execution reverted: GS026") })
    await assert.rejects(executeProposal(args(session, proposal)), (error) => {
      assert.equal(error.code, "simulation_failed")
      assert.match(error.message, /huidige eigenaar/)
      return true
    })
    assert.equal(state.sent.length, 0)
  })

  test("account switched during the send prompt: stale, a late hash still reaches the server", async () => {
    const { session, provider, proposal } = await ready()
    const pending = deferred()
    provider.handlers.eth_sendTransaction = () => pending.promise
    const posted = []
    const attempt = executeProposal(args(session, proposal, posted))
    while (session.state !== "awaiting_signature") await tick()
    provider.emit("accountsChanged", [KEYS.two.address])
    await assert.rejects(attempt, { code: "stale" })
    pending.resolve("0xlate")
    await tick()
    await tick()
    assert.deepEqual(posted, [{ url: urls.execution, body: { tx_hash: "0xlate" } }])
  })

  test("a hint the server refuses does not hide the on-chain result", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    const hints = []
    const http = { get: async () => proposal, post: async () => { throw new Error("500") } }
    const result = await executeProposal({ ...args(session, proposal), http, onHintFailed: (error) => hints.push(error) })
    assert.equal(result.outcome, "success")
    assert.equal(hints.length, 3)
  })

  test("an earlier hash is followed instead of sending twice", async () => {
    const { session, state, proposal } = await ready()
    const earlier = `0x${"e".repeat(64)}`
    state.transactions.set(earlier, { hash: earlier })
    state.receipts.set(earlier, executionReceipt({ hash: proposal.safe_tx_hash }))
    proposal.execution_tx_hash = earlier
    state.nonce = 6n
    const result = await executeProposal(args(session, proposal))
    assert.equal(result.txHash, earlier)
    assert.equal(state.sent.length, 0)
  })

  test("a server cannot pass off another transaction: the event must match the locally computed hash", async () => {
    const { session, state, proposal } = await ready()
    const other = `0x${"e".repeat(64)}`
    const otherHash = `0x${"77".repeat(32)}`
    state.transactions.set(other, { hash: other })
    state.receipts.set(other, executionReceipt({ hash: otherHash }))
    await assert.rejects(executeProposal(args(session, { ...proposal, execution_tx_hash: other, safe_tx_hash: otherHash })), { code: "hash_mismatch" })
    await assert.rejects(executeProposal(args(session, { ...proposal, execution_tx_hash: other })), { code: "execution_unconfirmed" })
    assert.equal(state.sent.length, 0)
  })

  test("a hash the chain does not know is ignored", async () => {
    const { session, state, proposal } = await ready()
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    const result = await executeProposal(args(session, { ...proposal, execution_tx_hash: `0x${"f".repeat(64)}` }))
    assert.equal(result.outcome, "success")
    assert.equal(state.sent.length, 1)
  })

  test("an earlier hash that reverted can be retried", async () => {
    const { session, state, proposal } = await ready()
    const earlier = `0x${"e".repeat(64)}`
    state.transactions.set(earlier, { hash: earlier })
    state.receipts.set(earlier, executionReceipt({ hash: proposal.safe_tx_hash, status: "0x0" }))
    state.onSend = (_tx, hash) => state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    await executeProposal(args(session, { ...proposal, execution_tx_hash: earlier }))
    assert.equal(state.sent.length, 1)
  })

  test("readiness is computed live", async () => {
    const { session, proposal } = await ready()
    const readiness = await executionReadiness({ session, http: server(proposal), urls, chain, safeAddress: SAFE })
    assert.deepEqual([readiness.ready, readiness.have, readiness.need, readiness.isNext], [true, 2, 2, true])

    const lowered = await ready({ threshold: 3n })
    const notYet = await executionReadiness({ session: lowered.session, http: server(lowered.proposal), urls, chain, safeAddress: SAFE })
    assert.equal(notYet.ready, false)
  })

  test("encodeSignatures refuses too few", () => {
    assert.throws(() => encodeSignatures([], 1n), { code: "not_enough_signatures" })
  })
})

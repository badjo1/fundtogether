import "./support/register.mjs"
import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { announce, fakeWindow, tick } from "./support/mock_provider.mjs"

const docListeners = new Map()
globalThis.document = {
  addEventListener: (name, fn) => { if (!docListeners.has(name)) docListeners.set(name, new Set()); docListeners.get(name).add(fn) },
  removeEventListener: (name, fn) => docListeners.get(name)?.delete(fn),
  querySelector: () => null
}
const win = fakeWindow()
globalThis.window = win

const { CHAIN_CONFIG, KEYS, SAFE, TOKEN, executionReceipt, fakeChain } = await import("./support/fake_chain.js")
const { getSession } = await import("wallet/session")
const { default: WalletController } = await import("controllers/wallet_controller")
const { default: WalletLinkController } = await import("controllers/wallet_link_controller")
const { default: SafeDeployController } = await import("controllers/safe_deploy_controller")
const { default: ProposalSignController } = await import("controllers/proposal_sign_controller")
const { default: ProposalExecuteController } = await import("controllers/proposal_execute_controller")
const { default: ContributeController } = await import("controllers/contribute_controller")
const { fakeElement } = await import("./support/stimulus_stub.js")
const { safeTxHash, typedDataPayload } = await import("safe/hash")
const { ZERO_ADDRESS } = await import("safe/constants")
const { encodeFunctionData } = await import("viem")
const { ERC20_ABI } = await import("safe/abi")
const { privateKeyToAccount } = await import("./support/vendor/viem_accounts.js")

const fake = fakeChain()
const session = getSession()
session.init({ userId: "1" })
announce(win, fake.provider)
await new Promise((resolve) => setTimeout(resolve, 350))
await session.connect()

function setRoutes(routes) {
  globalThis.fetch = async (url, options = {}) => {
    const handler = routes[`${options.method} ${url}`]
    if (!handler) throw new Error(`no route ${options.method} ${url}`)
    const body = options.body ? JSON.parse(options.body) : undefined
    return { status: 200, ok: true, headers: { get: () => "application/json" }, json: async () => handler(body) }
  }
}

function target(dataset = {}) {
  return { textContent: "", dataset }
}

function controller(Class, values, { message = target(), fields = [] } = {}) {
  const instance = new Class(fakeElement())
  Object.assign(instance, values, {
    hasMessageTarget: true,
    messageTarget: message,
    fieldTargets: fields,
    hasFieldTarget: fields.length > 0,
    hasAmountTarget: false
  })
  return instance
}

const eventNames = (instance) => instance.events.map((event) => event.name)
const stepNames = (instance) => instance.events.filter((event) => event.name === "step").map((event) => event.detail.step)

const data = encodeFunctionData({ abi: ERC20_ABI, functionName: "transfer", args: [KEYS.four.address, 1000000n] })
const tx = { to: TOKEN, value: 0n, data, operation: 0, safeTxGas: 0n, baseGas: 0n, gasPrice: 0n, gasToken: ZERO_ADDRESS, refundReceiver: ZERO_ADDRESS, nonce: 5n }
const baseProposal = {
  id: 1, kind: "transfer_token", title: "Test", params: { recipient: KEYS.four.address, amount: "1000000" }, state: "open",
  chain_id: 11155111, safe_address: SAFE, to: TOKEN, value: "0", data, operation: 0, safe_tx_gas: "0", base_gas: "0", gas_price: "0",
  gas_token: ZERO_ADDRESS, refund_receiver: ZERO_ADDRESS, nonce: "5", safe_tx_hash: safeTxHash({ chainId: 11155111, safe: SAFE, tx }),
  token: { address: TOKEN, symbol: "EURC", decimals: 6 }, signatures: [], execution_tx_hash: null
}

describe("controllers", () => {
  test("wallet: state events carry a derived status, never a stored linked flag", () => {
    const instance = controller(WalletController, {
      hasUserIdValue: true, userIdValue: "1", linkedAddressesValue: [], hasChainValue: true, chainValue: CHAIN_CONFIG, requiresChainValue: true,
      hasProviderListTarget: false, hasProviderTemplateTarget: false
    })
    instance.connect()
    const first = instance.events.at(-1).detail
    assert.equal(first.state, "connected")
    assert.equal(first.status, "unlinked")
    assert.equal(instance.element.dataset.walletStatus, "unlinked")

    instance.linkedAddressesValue = [KEYS.one.address]
    instance.linkedAddressesValueChanged()
    assert.equal(instance.events.at(-1).detail.status, "ready")

    instance.disconnect()
    const before = instance.events.length
    fake.provider.emit("chainChanged", "0xaa36a7")
    session.publish()
    assert.equal(instance.events.length, before)
  })

  test("wallet: Turbo cache reset clears the UI, and listeners do not pile up over visits", () => {
    const message = target()
    const field = target({ field: "address" })
    for (let visit = 0; visit < 3; visit += 1) {
      const instance = controller(WalletController, {
        hasUserIdValue: true, userIdValue: "1", linkedAddressesValue: [], hasChainValue: false, chainValue: {}, requiresChainValue: false,
        hasProviderListTarget: false, hasProviderTemplateTarget: false
      }, { message, fields: [field] })
      instance.connect()
      assert.equal(field.textContent, KEYS.one.address)
      docListeners.get("turbo:before-cache").forEach((listener) => listener())
      assert.equal(field.textContent, "")
      assert.equal(instance.element.dataset.walletState, undefined)
      instance.disconnect()
    }
    assert.equal(docListeners.get("turbo:before-cache").size, 0)
    assert.equal(fake.provider.listenerCount("accountsChanged"), 1)
  })

  test("wallet-link: linked is only dispatched after the server confirms", async () => {
    const message = "x wants you to sign in:\n" + KEYS.one.address + "\nNonce: n1"
    setRoutes({
      "POST /wallet_challenges": () => ({ nonce: "n1", message }),
      "POST /wallets": () => ({ id: 9, address: KEYS.one.address })
    })
    const instance = controller(WalletLinkController, { challengesUrlValue: "/wallet_challenges", walletsUrlValue: "/wallets" })
    await instance.link()
    assert.deepEqual(stepNames(instance), ["challenge", "sign_message", "saving_link", "linked"])
    assert.equal(eventNames(instance).at(-1), "linked")
    assert.equal(instance.events.at(-1).detail.wallet.id, 9)
  })

  test("wallet-link: a server refusal is an error event with the Dutch server message", async () => {
    setRoutes({ "POST /wallet_challenges": () => ({ nonce: "n1", message: "no address" }) })
    const element = controller(WalletLinkController, { challengesUrlValue: "/wallet_challenges", walletsUrlValue: "/wallets" })
    await element.link()
    assert.equal(eventNames(element).at(-1), "error")
    assert.equal(element.events.at(-1).detail.code, "challenge_mismatch")
    assert.equal(element.messageTarget.dataset.tone, "refusal")
    assert.ok(!eventNames(element).includes("linked"))
  })

  const signValues = {
    proposalUrlValue: "/p/1", signaturesUrlValue: "/p/1/signatures", chainValue: CHAIN_CONFIG, safeAddressValue: SAFE, linkedAddressesValue: [KEYS.one.address]
  }

  test("proposal-sign: refuses without a review, and signs after one", async () => {
    let posted = null
    setRoutes({
      "GET /p/1": () => baseProposal,
      "POST /p/1/signatures": (body) => { posted = body; return baseProposal }
    })
    const field = target({ field: "summary" })
    const hashField = target({ field: "safeTxHash" })
    const instance = controller(ProposalSignController, signValues, { fields: [field, hashField] })

    await instance.sign()
    assert.equal(instance.events.at(-1).detail.code, "proposal_not_reviewed")
    assert.equal(posted, null)

    await instance.review()
    assert.match(field.textContent, /^Stuur 1,00 EURC naar 0x/)
    assert.equal(hashField.textContent, baseProposal.safe_tx_hash)
    assert.ok(eventNames(instance).includes("reviewed"))
    assert.ok(!eventNames(instance).includes("signed"))

    await instance.sign()
    assert.equal(eventNames(instance).at(-1), "signed")
    assert.match(posted.signature, /^0x[0-9a-f]{130}$/)
  })

  test("proposal-sign: a tampered server hash gives an error, no prompt, no post", async () => {
    let posted = false
    setRoutes({
      "GET /p/1": () => ({ ...baseProposal, safe_tx_hash: `0x${"ab".repeat(32)}` }),
      "POST /p/1/signatures": () => { posted = true; return {} }
    })
    const signedBefore = fake.state.signed.length
    const instance = controller(ProposalSignController, signValues)
    await instance.review()
    assert.equal(instance.events.at(-1).detail.code, "hash_mismatch")
    assert.equal(instance.events.at(-1).detail.refusal, true)
    assert.equal(fake.state.signed.length, signedBefore)
    assert.equal(posted, false)
  })

  test("proposal-sign: Turbo cache reset forgets the review", async () => {
    setRoutes({ "GET /p/1": () => baseProposal })
    const instance = controller(ProposalSignController, signValues)
    instance.connect()
    await instance.review()
    assert.ok(instance.reviewedHash)
    docListeners.get("turbo:before-cache").forEach((listener) => listener())
    assert.equal(instance.reviewedHash, null)
    instance.disconnect()
  })

  test("proposal-execute: success only after the receipt; a double click does not send twice", async () => {
    const typed = JSON.parse(typedDataPayload({ chainId: 11155111, safe: SAFE, tx }))
    const signatures = await Promise.all([KEYS.one, KEYS.two].map(async (entry) => ({
      signer: entry.address,
      signature: await privateKeyToAccount(entry.key).signTypedData(typed)
    })))
    const proposal = { ...baseProposal, signatures }
    setRoutes({
      "GET /p/1": () => proposal,
      "POST /p/1/execution": () => proposal,
      "POST /sync": () => ({})
    })
    fake.state.onSend = (_tx, hash) => fake.state.receipts.set(hash, executionReceipt({ hash: proposal.safe_tx_hash }))
    const sentBefore = fake.state.sent.length

    const instance = controller(ProposalExecuteController, {
      proposalUrlValue: "/p/1", executionUrlValue: "/p/1/execution", syncUrlValue: "/sync", chainValue: CHAIN_CONFIG, safeAddressValue: SAFE
    })
    await instance.check()
    assert.equal(instance.element.dataset.executionReady, "true")

    await Promise.all([instance.execute(), instance.execute()])
    assert.equal(fake.state.sent.length, sentBefore + 1)
    assert.equal(eventNames(instance).at(-1), "executed")
    const steps = stepNames(instance)
    assert.ok(steps.indexOf("waiting_receipt") < steps.indexOf("executed"))
    fake.state.onSend = null
  })

  test("contribute: balances on RPC failure stay empty and report an error", async () => {
    const field = target({ field: "fundBalance" })
    field.textContent = "99"
    const instance = controller(ContributeController, { syncUrlValue: "/sync", chainValue: CHAIN_CONFIG, tokenAddressValue: TOKEN, safeAddressValue: SAFE }, { fields: [field] })
    const original = fake.provider.handlers.eth_call
    fake.provider.handlers.eth_call = () => { throw new Error("rpc down") }
    await instance.refreshBalances()
    fake.provider.handlers.eth_call = original
    assert.equal(field.textContent, "")
    assert.equal(instance.events.at(-1).name, "error")
    assert.equal(instance.events.at(-1).detail.code, "chain_read_failed")
  })

  test("contribute: an empty amount is refused with Dutch text", async () => {
    const instance = controller(ContributeController, { syncUrlValue: "/sync", chainValue: CHAIN_CONFIG, tokenAddressValue: TOKEN, safeAddressValue: SAFE })
    await instance.contribute()
    assert.equal(instance.events.at(-1).detail.code, "invalid_amount")
    assert.match(instance.messageTarget.textContent, /geldig bedrag/)
  })

  test("safe-deploy: an error from a bad deployment is an error event", async () => {
    setRoutes({ "GET /a/safe": () => ({ chain_id: 11155111 }) })
    const instance = controller(SafeDeployController, { urlValue: "/a/safe", chainValue: CHAIN_CONFIG, createParamsValue: {}, acknowledgeRiskValue: false })
    await instance.deploy()
    assert.equal(instance.events.at(-1).name, "error")
    assert.equal(instance.events.at(-1).detail.code, "deployment_malformed")
    assert.ok(!eventNames(instance).includes("deployed"))
  })
})

await tick()

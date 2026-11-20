import "./support/register.mjs"
import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { MockProvider, announce, deferred, fakeTimers, fakeWindow, providerError, tick } from "./support/mock_provider.mjs"

const { WalletSession, deriveStatus } = await import("wallet/session")
const { normalizeChain } = await import("wallet/chains")
const { CHAIN_CONFIG, KEYS } = await import("./support/fake_chain.js")

const A = KEYS.one.address
const B = KEYS.two.address
const SEPOLIA = "0xaa36a7"
const chain = normalizeChain(CHAIN_CONFIG)

function basics(overrides = {}) {
  return new MockProvider({
    eth_requestAccounts: [A],
    eth_accounts: [A],
    eth_chainId: SEPOLIA,
    ...overrides
  })
}

function setup({ provider = basics(), win = fakeWindow(), announceIt = true, userId = "7" } = {}) {
  const timers = fakeTimers()
  const session = new WalletSession({ window: win, setTimer: timers.setTimer, clearTimer: timers.clearTimer })
  const states = []
  session.subscribe((snapshot) => states.push(snapshot.state))
  session.init({ userId })
  if (announceIt) announce(win, provider)
  timers.fire(300)
  return { session, provider, win, timers, states }
}

async function connected(options) {
  const context = setup(options)
  await tick()
  await context.session.connect()
  return context
}

describe("discovery and restore", () => {
  test("idle to discovering to disconnected when providers exist", async () => {
    const { session, states } = setup()
    await tick()
    assert.equal(session.state, "disconnected")
    assert.deepEqual(states, ["idle", "discovering", "discovering", "disconnected"])
  })

  test("no provider gives no_wallet, late announce moves to disconnected", async () => {
    const win = fakeWindow()
    const { session } = setup({ win, announceIt: false })
    assert.equal(session.state, "no_wallet")
    announce(win, basics())
    assert.equal(session.state, "disconnected")
  })

  test("connect without a wallet gives the device-specific error", async () => {
    const desktop = setup({ announceIt: false })
    await assert.rejects(desktop.session.connect(), { code: "no_wallet_desktop" })
    const mobile = setup({ announceIt: false, win: fakeWindow({ userAgent: "Mozilla/5.0 (iPhone) Safari" }) })
    await assert.rejects(mobile.session.connect(), { code: "no_wallet_mobile" })
    const social = setup({ announceIt: false, win: fakeWindow({ userAgent: "Mozilla/5.0 (iPhone) Instagram 300" }) })
    await assert.rejects(social.session.connect(), { code: "in_app_browser" })
  })

  test("legacy window.ethereum is used when nothing announces", async () => {
    const ethereum = basics()
    const { session } = setup({ win: fakeWindow({ ethereum }), announceIt: false })
    assert.equal(session.state, "disconnected")
    assert.deepEqual(session.snapshot().wallets.map((wallet) => wallet.name), ["Browserwallet"])
    await session.connect()
    assert.equal(session.state, "connected")
  })

  test("several wallets need a choice", async () => {
    const win = fakeWindow()
    const context = setup({ win })
    announce(win, basics(), { uuid: "uuid-2", rdns: "other.wallet" })
    await tick()
    await assert.rejects(context.session.connect(), { code: "wallet_choice_required" })
    await context.session.connect("uuid-2")
    assert.equal(context.session.state, "connected")
    assert.equal(context.session.snapshot().wallet.rdns, "other.wallet")
  })

  test("restore after reload is silent, through eth_accounts only", async () => {
    const win = fakeWindow()
    const first = await connected({ win })
    assert.equal(first.session.state, "connected")
    const provider = basics()
    const second = setup({ win, provider })
    await tick()
    assert.equal(second.session.state, "connected")
    assert.equal(provider.callsTo("eth_requestAccounts").length, 0)
  })

  test("restore with no accounts clears the hint and stays disconnected", async () => {
    const win = fakeWindow()
    await connected({ win })
    const second = setup({ win, provider: basics({ eth_accounts: [] }) })
    await tick()
    assert.equal(second.session.state, "disconnected")
    assert.equal(win.localStorage.getItem("ft.wallet"), null)
  })

  test("the hint of another user is not restored", async () => {
    const win = fakeWindow()
    await connected({ win, userId: "1" })
    const provider = basics()
    const second = setup({ win, provider, userId: "2" })
    await tick()
    assert.equal(second.session.state, "disconnected")
    assert.equal(provider.callsTo("eth_accounts").length, 0)
    assert.equal(win.localStorage.getItem("ft.wallet"), null)
  })

  test("a different user on the same page lifetime drops the connection", async () => {
    const { session } = await connected({ userId: "1" })
    session.init({ userId: "2" })
    assert.equal(session.state, "disconnected")
    assert.equal(session.address, null)
  })

  test("broken localStorage does not break anything", async () => {
    const win = fakeWindow()
    win.localStorage = { getItem() { throw new Error("denied") }, setItem() { throw new Error("denied") }, removeItem() { throw new Error("denied") } }
    const { session } = await connected({ win })
    assert.equal(session.state, "connected")
  })
})

describe("connect", () => {
  test("rejection returns to disconnected, neutral", async () => {
    const provider = basics({ eth_requestAccounts: () => { throw providerError(4001, "User rejected") } })
    const { session } = setup({ provider })
    await tick()
    await assert.rejects(session.connect(), (error) => error.code === "user_rejected" && error.neutral === true)
    assert.equal(session.state, "disconnected")
    assert.equal(session.snapshot().notice.neutral, true)
  })

  test("-32002 goes to wallet_busy and an explicit click retries", async () => {
    let busy = true
    const provider = basics({
      eth_requestAccounts: () => {
        if (busy) throw providerError(-32002, "already pending")
        return [A]
      }
    })
    const { session } = setup({ provider })
    await tick()
    await assert.rejects(session.connect(), { code: "wallet_busy" })
    assert.equal(session.state, "wallet_busy")
    busy = false
    await session.connect()
    assert.equal(session.state, "connected")
  })

  test("wallet_busy resolves on accountsChanged once the wallet answers", async () => {
    const provider = basics({ eth_requestAccounts: () => { throw providerError(-32002) } })
    const { session } = setup({ provider })
    await tick()
    await assert.rejects(session.connect(), { code: "wallet_busy" })
    provider.emit("accountsChanged", [A])
    await tick()
    assert.equal(session.state, "connected")
  })

  test("a banner appears after 60 s and reset drops a late answer", async () => {
    const pending = deferred()
    const provider = basics({ eth_requestAccounts: () => pending.promise })
    const { session, timers } = setup({ provider })
    await tick()
    const attempt = session.connect()
    assert.equal(session.state, "requesting_accounts")
    timers.fire(60_000)
    assert.equal(session.banner, "open_wallet")
    session.resetPending()
    assert.equal(session.state, "disconnected")
    pending.resolve([A])
    await attempt
    assert.equal(session.state, "disconnected")
    assert.equal(session.address, null)
  })

  test("connected is not linked: status comes from the page's linked list", async () => {
    const { session } = await connected()
    const snapshot = session.snapshot()
    assert.equal(snapshot.state, "connected")
    assert.equal(deriveStatus(snapshot, { linked: [] }), "unlinked")
    assert.equal(deriveStatus(snapshot, { linked: [B] }), "address_mismatch")
    assert.equal(deriveStatus(snapshot, { linked: [A.toUpperCase().replace("0X", "0x")] }), "ready")
    assert.equal(deriveStatus(snapshot, { linked: [A], requiresChain: true, requiredChainId: 100 }), "wrong_network")
    assert.equal(deriveStatus(snapshot, { linked: [A], requiresChain: true, requiredChainId: 11155111 }), "ready")
    assert.equal(deriveStatus({ state: "disconnected" }, { linked: [A] }), "disconnected")
  })
})

describe("provider events", () => {
  test("accountsChanged updates, empty disconnects, chainChanged parses hex", async () => {
    const { session, provider } = await connected()
    provider.emit("accountsChanged", [B.toUpperCase().replace("0X", "0x")])
    assert.equal(session.address, B)
    provider.emit("chainChanged", "0x64")
    assert.equal(session.chainId, 100)
    provider.emit("accountsChanged", [])
    assert.equal(session.state, "disconnected")
    assert.equal(session.address, null)
  })

  test("disconnect ends the session, except MetaMask's 1013 reconnect", async () => {
    const { session, provider } = await connected()
    provider.emit("disconnect", { code: 1013 })
    assert.equal(session.state, "connected")
    provider.emit("disconnect", { code: 4900 })
    assert.equal(session.state, "disconnected")
    assert.equal(session.snapshot().notice.code, "session_ended")
  })

  test("listeners do not multiply over connects and subscribers", async () => {
    const { session, provider } = await connected()
    for (let visit = 0; visit < 5; visit += 1) {
      const stop = session.subscribe(() => {})
      session.init({ userId: "7" })
      stop()
    }
    session.disconnect()
    await session.connect()
    assert.equal(provider.listenerCount("accountsChanged"), 1)
    assert.equal(provider.listenerCount("chainChanged"), 1)
    assert.equal(provider.listenerCount("disconnect"), 1)
  })

  test("disconnect stops listening and clears the hint", async () => {
    const { session, provider, win } = await connected()
    session.disconnect()
    assert.equal(provider.listenerCount("accountsChanged"), 0)
    assert.equal(win.localStorage.getItem("ft.wallet"), null)
    provider.emit("accountsChanged", [B])
    assert.equal(session.state, "disconnected")
    assert.equal(session.address, null)
  })
})

describe("chain switch", () => {
  function switching(handlers) {
    let current = SEPOLIA
    return basics({
      eth_chainId: () => current,
      wallet_switchEthereumChain: ([{ chainId }]) => {
        if (handlers.switch) handlers.switch(chainId)
        current = chainId
        return null
      },
      wallet_addEthereumChain: (params) => {
        if (handlers.add) handlers.add(params)
        return null
      }
    })
  }

  const target = normalizeChain({ ...CHAIN_CONFIG, chain_id: 100, name: "Gnosis", native_symbol: "xDAI", rpc_urls: ["https://rpc.gnosischain.com"] })

  test("switches and confirms by re-reading", async () => {
    const { session } = await connected({ provider: switching({}) })
    await session.switchChain(target)
    assert.equal(session.state, "connected")
    assert.equal(session.chainId, 100)
  })

  test("4902 adds the chain and switches", async () => {
    let added = null
    let first = true
    const provider = switching({
      switch: () => {
        if (first) {
          first = false
          throw providerError(4902, "Unrecognized chain")
        }
      },
      add: ([params]) => { added = params }
    })
    const { session } = await connected({ provider })
    await session.switchChain(target)
    assert.equal(session.chainId, 100)
    assert.equal(added.chainId, "0x64")
    assert.equal(added.nativeCurrency.symbol, "xDAI")
  })

  test("MetaMask mobile's wrapped 4902 also adds the chain", async () => {
    let added = false
    let first = true
    const provider = switching({
      switch: () => {
        if (first) {
          first = false
          throw providerError(-32603, "Internal", { data: { originalError: { code: 4902 } } })
        }
      },
      add: () => { added = true }
    })
    const { session } = await connected({ provider })
    await session.switchChain(target)
    assert.equal(added, true)
  })

  test("4001 stays connected on the old chain, neutral", async () => {
    const provider = switching({ switch: () => { throw providerError(4001) } })
    const { session } = await connected({ provider })
    await assert.rejects(session.switchChain(target), (error) => error.code === "user_rejected" && error.neutral)
    assert.equal(session.state, "connected")
    assert.equal(session.chainId, 11155111)
  })

  test("4200 gives the manual instruction", async () => {
    const provider = switching({ switch: () => { throw providerError(4200) } })
    const { session } = await connected({ provider })
    await assert.rejects(session.switchChain(target), { code: "chain_switch_failed" })
    assert.equal(session.state, "connected")
  })

  test("rejecting the add stays connected", async () => {
    const provider = switching({ switch: () => { throw providerError(4902) }, add: () => { throw providerError(-32000, "nope") } })
    const { session } = await connected({ provider })
    await assert.rejects(session.switchChain(target), { code: "chain_add_failed" })
    assert.equal(session.state, "connected")
  })

  test("a wallet that claims success but stays put is an error", async () => {
    const provider = basics({ wallet_switchEthereumChain: null })
    const { session } = await connected({ provider })
    await assert.rejects(session.switchChain(target), { code: "chain_switch_failed" })
  })
})

describe("signature requests", () => {
  const expected = { address: A, chainId: 11155111 }

  test("wrong network is refused before any prompt", async () => {
    const provider = basics({ eth_chainId: "0x64", personal_sign: "0xsig" })
    const { session } = await connected({ provider })
    await assert.rejects(session.request("personal_sign", ["0x", A], { expected }), { code: "wrong_network" })
    assert.equal(provider.callsTo("personal_sign").length, 0)
    assert.equal(session.state, "connected")
  })

  test("wrong account is refused before any prompt, using the wallet's live answer", async () => {
    let accounts = [A]
    const provider = basics({ eth_accounts: () => accounts, personal_sign: "0xsig" })
    const { session } = await connected({ provider })
    accounts = [B]
    await assert.rejects(session.request("personal_sign", ["0x", A], { expected }), { code: "wrong_account" })
    assert.equal(provider.callsTo("personal_sign").length, 0)
  })

  test("success goes through awaiting_signature", async () => {
    const provider = basics({ personal_sign: "0xsig" })
    const { session, states } = await connected({ provider })
    assert.equal(await session.request("personal_sign", ["0x", A], { expected }), "0xsig")
    assert.ok(states.includes("awaiting_signature"))
    assert.equal(session.state, "connected")
  })

  test("rejection returns to connected, neutral", async () => {
    const provider = basics({ personal_sign: () => { throw providerError(4001) } })
    const { session } = await connected({ provider })
    await assert.rejects(session.request("personal_sign", ["0x", A], { expected }), { code: "user_rejected" })
    assert.equal(session.state, "connected")
  })

  test("account switched mid-flow goes stale and ignores the late result", async () => {
    const pending = deferred()
    const provider = basics({ personal_sign: () => pending.promise })
    const { session } = await connected({ provider })
    const attempt = session.request("personal_sign", ["0x", A], { expected })
    await tick()
    assert.equal(session.state, "awaiting_signature")
    provider.emit("accountsChanged", [B])
    await assert.rejects(attempt, { code: "stale" })
    assert.equal(session.state, "stale")
    pending.resolve("0xlate")
    await tick()
    assert.equal(session.state, "stale")
    session.acknowledgeStale()
    assert.equal(session.state, "connected")
    assert.equal(session.address, B)
  })

  test("chain switched mid-flow goes stale", async () => {
    const pending = deferred()
    const provider = basics({ personal_sign: () => pending.promise })
    const { session } = await connected({ provider })
    const attempt = session.request("personal_sign", ["0x", A], { expected })
    await tick()
    provider.emit("chainChanged", "0x64")
    await assert.rejects(attempt, { code: "stale" })
    assert.equal(session.chainId, 100)
  })

  test("a late transaction hash after going stale reaches onLate", async () => {
    const pending = deferred()
    const provider = basics({ eth_sendTransaction: () => pending.promise })
    const { session } = await connected({ provider })
    let late = null
    const attempt = session.request("eth_sendTransaction", [{}], { expected, onLate: (hash) => { late = hash } })
    await tick()
    provider.emit("accountsChanged", [B])
    await assert.rejects(attempt, { code: "stale" })
    pending.resolve("0xhash")
    await tick()
    assert.equal(late, "0xhash")
  })

  test("a second prompt while one is open is refused, not queued", async () => {
    const pending = deferred()
    const provider = basics({ personal_sign: () => pending.promise })
    const { session } = await connected({ provider })
    const first = session.request("personal_sign", ["0x", A], { expected })
    await tick()
    await assert.rejects(session.request("personal_sign", ["0x", A], { expected }), { code: "wallet_action_pending" })
    pending.resolve("0xsig")
    await first
    assert.equal(provider.callsTo("personal_sign").length, 1)
  })

  test("-32002 on a signature gives wallet_busy, and the next action recovers", async () => {
    let busy = true
    const provider = basics({
      personal_sign: () => {
        if (busy) throw providerError(-32002)
        return "0xsig"
      }
    })
    const { session } = await connected({ provider })
    await assert.rejects(session.request("personal_sign", ["0x", A], { expected }), { code: "wallet_busy" })
    assert.equal(session.state, "wallet_busy")
    busy = false
    assert.equal(await session.request("personal_sign", ["0x", A], { expected }), "0xsig")
  })

  test("banners at 45 s and 120 s, and reset abandons", async () => {
    const pending = deferred()
    const provider = basics({ personal_sign: () => pending.promise })
    const { session, timers } = await connected({ provider })
    const attempt = session.request("personal_sign", ["0x", A], { expected })
    await tick()
    timers.fire(45_000)
    assert.equal(session.banner, "open_wallet")
    timers.fire(120_000)
    assert.equal(session.banner, "offer_reset")
    session.resetPending()
    await assert.rejects(attempt, { code: "user_rejected" })
    assert.equal(session.state, "connected")
    pending.resolve("0xlate")
    await tick()
    assert.equal(session.state, "connected")
  })

  test("not connected is refused", async () => {
    const { session } = setup()
    await tick()
    await assert.rejects(session.request("personal_sign", [], { expected }), { code: "not_connected" })
  })

  test("wallet disconnect during a prompt rejects it", async () => {
    const pending = deferred()
    const provider = basics({ personal_sign: () => pending.promise })
    const { session } = await connected({ provider })
    const attempt = session.request("personal_sign", ["0x", A], { expected })
    await tick()
    provider.emit("disconnect", { code: 4900 })
    await assert.rejects(attempt, { code: "session_ended" })
    assert.equal(session.state, "disconnected")
  })

  test("submit returns to connected on failure as well", async () => {
    const provider = basics({ personal_sign: "0xsig" })
    const { session } = await connected({ provider })
    await session.request("personal_sign", ["0x", A], { expected, keepSubmitting: true })
    assert.equal(session.state, "submitting")
    await assert.rejects(session.submit(async () => { throw new Error("boom") }))
    assert.equal(session.state, "connected")
  })

  test("illegal transitions throw instead of drifting", async () => {
    const { session } = await connected()
    assert.throws(() => session.go("restoring"), /Illegal wallet transition/)
  })
})

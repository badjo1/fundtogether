import "./support/register.mjs"
import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { MockProvider, announce, deferred, fakeTimers, fakeWindow, providerError, tick } from "./support/mock_provider.mjs"

const { Discovery } = await import("wallet/discovery")
const { MESSAGES, SAFE_REVERTS, WalletError, normalizeError, revertCode } = await import("wallet/errors")
const { detectEnvironment, noWalletCode, walletDeepLinks } = await import("wallet/environment")
const { addChainParams, normalizeChain, parseChainId } = await import("wallet/chains")
const { createHttp } = await import("wallet/http")
const { createHandoff, linkWallet, utf8ToHex } = await import("wallet/link")
const { WalletSession } = await import("wallet/session")
const { loadWalletConnect, walletConnectEnabled } = await import("wallet/walletconnect")
const { fakeChain, KEYS } = await import("./support/fake_chain.js")
const { recoverAddress, hashMessage } = await import("viem")

describe("error normalisation", () => {
  const cases = [
    [providerError(4001), "user_rejected"],
    [providerError(-32002), "wallet_busy"],
    [providerError(4100), "unauthorized"],
    [providerError(4200), "unsupported_method"],
    [providerError(4900), "wallet_disconnected"],
    [providerError(4901), "chain_disconnected"],
    [providerError(4902), "chain_not_added"],
    [providerError(-32603, "x", { data: { originalError: { code: 4902 } } }), "chain_not_added"],
    [providerError(-32603, "x", { data: { originalError: { code: 4001 } } }), "user_rejected"],
    [providerError(-32603, "Unrecognized chain ID 0x64"), "chain_not_added"],
    [providerError(5000, "User rejected methods."), "user_rejected"],
    [{ code: "ACTION_REJECTED" }, "user_rejected"],
    [new Error("User denied transaction signature"), "user_rejected"],
    [providerError(-32000, "insufficient funds for gas * price + value"), "insufficient_gas"],
    [providerError(3, "execution reverted: GS026"), "simulation_failed"],
    [new Error("something odd"), "wallet_error"]
  ]
  for (const [raw, code] of cases) {
    test(`${raw.code ?? raw.message} to ${code}`, () => assert.equal(normalizeError(raw).code, code))
  }

  test("a WalletError passes through unchanged", () => {
    const error = new WalletError("stale")
    assert.equal(normalizeError(error), error)
  })

  test("user rejection is the only neutral error", () => {
    const neutral = Object.keys(MESSAGES).filter((code) => new WalletError(code).neutral)
    assert.deepEqual(neutral, ["user_rejected"])
  })

  test("GS codes are found in text and in hex revert data, and carry Dutch text", () => {
    assert.equal(revertCode({ message: "execution reverted: GS013" }), "GS013")
    assert.equal(revertCode({ data: { data: "0x08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000054753303236000000000000000000000000000000000000000000000000000000" } }), "GS026")
    assert.equal(revertCode({ message: "nothing here" }), null)
    assert.match(normalizeError(providerError(3, "execution reverted: GS020")).message, /te weinig handtekeningen/)
    assert.ok(Object.values(SAFE_REVERTS).every((text) => text.length > 0))
  })

  test("every message is non-empty text", () => {
    for (const [code, text] of Object.entries(MESSAGES)) {
      assert.equal(typeof text, "string", code)
      assert.ok(text.length > 5, code)
      assert.equal(new WalletError(code).message, text)
    }
  })
})

describe("discovery", () => {
  test("listens before requesting, keeps duplicates out, cleans icons", () => {
    const win = new (class extends EventTarget { Event = Event })()
    const seen = []
    win.addEventListener("eip6963:requestProvider", () => {
      seen.push("request")
      win.dispatchEvent(new CustomEvent("eip6963:announceProvider", {
        detail: { info: { uuid: "a", name: "W", icon: "https://evil.example/x.png", rdns: "w" }, provider: { request() {} } }
      }))
    })
    const discovery = new Discovery(win)
    discovery.start()
    assert.deepEqual(seen, ["request"])
    assert.equal(discovery.list().length, 1)
    assert.equal(discovery.list()[0].icon, null)

    const second = { request() {} }
    win.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail: { info: { uuid: "a", name: "Fake" }, provider: second } }))
    assert.equal(discovery.list().length, 1)
    assert.notEqual(discovery.list()[0].provider, second)
    assert.equal(discovery.list()[0].name, "W")
  })

  test("ignores malformed announcements", () => {
    const win = fakeWindow()
    const discovery = new Discovery(win)
    discovery.start()
    win.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail: { info: { uuid: "x" }, provider: {} } }))
    win.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail: {} }))
    assert.equal(discovery.list().length, 0)
  })

  test("legacy goes away as soon as a 6963 wallet announces", () => {
    const win = fakeWindow({ ethereum: { request() {} } })
    const discovery = new Discovery(win)
    discovery.start()
    assert.equal(discovery.list()[0].legacy, true)
    announce(win, new MockProvider())
    assert.equal(discovery.list().length, 1)
    assert.equal(discovery.list()[0].legacy, false)
  })
})

describe("environment", () => {
  test("recognises phones and social webviews", () => {
    assert.equal(detectEnvironment("Mozilla/5.0 (iPhone; CPU iPhone OS) Instagram 300").socialWebview, true)
    assert.equal(detectEnvironment("Mozilla/5.0 (Linux; Android 14) FB_IAB/FB4A").socialWebview, true)
    assert.equal(detectEnvironment("Mozilla/5.0 (Linux; Android 14) Chrome/130").mobile, true)
    assert.equal(detectEnvironment("Mozilla/5.0 (Macintosh)").mobile, false)
    assert.equal(detectEnvironment("Mozilla/5.0 (iPhone) MetaMaskMobile").walletBrowser, true)
    assert.equal(noWalletCode(detectEnvironment("x Telegram")), "in_app_browser")
  })

  test("deep links only for https", () => {
    const links = walletDeepLinks("https://fundtogether.example/wallet/handoff/abc?x=1")
    assert.equal(links.metamask, "https://link.metamask.io/dapp/fundtogether.example/wallet/handoff/abc?x=1")
    assert.match(links.trust, /^https:\/\/link\.trustwallet\.com\/open_url\?coin_id=60&url=https%3A%2F%2F/)
    assert.deepEqual(walletDeepLinks("http://localhost:3000/x"), {})
  })
})

describe("chain config", () => {
  test("accepts the registry shape and only https RPCs", () => {
    const chain = normalizeChain({
      chain_id: 100, name: "Gnosis", native_symbol: "xDAI", explorer_url: "https://gnosisscan.io",
      rpc_urls: ["https://rpc.gnosischain.com", "http://evil.example", "http://localhost:8545"],
      token: { symbol: "EURe", address: "0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430", decimals: 18 }
    })
    assert.deepEqual([...chain.rpcUrls], ["https://rpc.gnosischain.com", "http://localhost:8545"])
    assert.equal(chain.tokens[0].address, "0x420ca0f9b9b604ce0fd9c18ef134c705e5fa3430")
    const params = addChainParams(chain)
    assert.equal(params.chainId, "0x64")
    assert.deepEqual(params.blockExplorerUrls, ["https://gnosisscan.io"])
  })

  test("parses chain ids strictly", () => {
    assert.equal(parseChainId("0x64"), 100)
    assert.equal(parseChainId("100"), 100)
    assert.equal(parseChainId(100), 100)
    assert.equal(parseChainId("abc"), null)
    assert.equal(parseChainId(1.5), null)
    assert.equal(parseChainId(null), null)
    assert.throws(() => normalizeChain({}), { code: "chain_read_mismatch" })
  })
})

describe("http", () => {
  const response = (status, body, type = "application/json") => ({
    status,
    ok: status >= 200 && status < 300,
    headers: { get: () => type },
    json: async () => body
  })
  const doc = { querySelector: () => ({ content: "csrf-token" }) }

  test("sends JSON with the CSRF token and returns the payload", async () => {
    let seen = null
    const http = createHttp({ document: doc, fetch: async (url, options) => { seen = { url, options }; return response(200, { ok: 1 }) } })
    assert.deepEqual(await http.post("/x", { a: 1 }), { ok: 1 })
    assert.equal(seen.options.headers["X-CSRF-Token"], "csrf-token")
    assert.equal(seen.options.body, '{"a":1}')
    assert.equal(seen.options.credentials, "same-origin")
  })

  test("server errors keep the Dutch message and the code", async () => {
    const http = createHttp({ document: doc, fetch: async () => response(422, { error: "not_owner", message: "Geen eigenaar." }) })
    await assert.rejects(http.get("/x"), (error) => error.code === "server_rejected" && error.message === "Geen eigenaar." && error.details.error === "not_owner")
  })

  test("a redirect to the login page counts as an expired session", async () => {
    const http = createHttp({ document: doc, fetch: async () => response(200, null, "text/html") })
    await assert.rejects(http.get("/x"), { code: "session_expired" })
  })

  test("network failure", async () => {
    const http = createHttp({ document: doc, fetch: async () => { throw new TypeError("Failed to fetch") } })
    await assert.rejects(http.get("/x"), { code: "server_unreachable" })
  })
})

describe("link flow", () => {
  const address = KEYS.one.address
  const message = `fundtogether.test wants you to sign in with your Ethereum account:\n${address}\n\nKoppel deze wallet.\n\nNonce: abc123`

  async function linked(chainOverrides = {}) {
    const { state, provider } = fakeChain(chainOverrides)
    const win = fakeWindow()
    const timers = fakeTimers()
    const session = new WalletSession({ window: win, setTimer: timers.setTimer, clearTimer: timers.clearTimer })
    session.init({ userId: "1" })
    announce(win, provider)
    timers.fire(300)
    await session.connect()
    return { session, state, provider }
  }

  function server(overrides = {}) {
    const calls = []
    return {
      calls,
      post: async (url, body) => {
        calls.push({ url, body })
        if (url === "/wallet_challenges") return overrides.challenge ?? { nonce: "abc123", message }
        return overrides.wallet ?? { id: 1, address }
      }
    }
  }

  const urls = { challenges: "/wallet_challenges", wallets: "/wallets" }

  test("challenge, personal_sign of the hex message, post; the signature really recovers", async () => {
    const { session, state } = await linked()
    const http = server()
    const steps = []
    const wallet = await linkWallet({ session, http, urls, onStep: (step) => steps.push(step) })
    assert.deepEqual(wallet, { id: 1, address })
    assert.deepEqual(steps, ["challenge", "sign_message", "saving_link"])
    assert.deepEqual(http.calls[0].body, { address, purpose: "link" })
    const posted = http.calls[1].body
    assert.equal(posted.nonce, "abc123")
    assert.equal(state.signed[0].message, utf8ToHex(message))
    assert.equal((await recoverAddress({ hash: hashMessage(message), signature: posted.signature })).toLowerCase(), address)
    assert.equal(session.state, "connected")
  })

  test("not connected is refused before any request", async () => {
    const timers = fakeTimers()
    const session = new WalletSession({ window: fakeWindow(), setTimer: timers.setTimer, clearTimer: timers.clearTimer })
    const http = server()
    await assert.rejects(linkWallet({ session, http, urls }), { code: "not_connected" })
    assert.equal(http.calls.length, 0)
  })

  test("a challenge for another address is not signed", async () => {
    const { session, state } = await linked()
    const http = server({ challenge: { nonce: "abc123", message: message.replace(address, KEYS.two.address) } })
    await assert.rejects(linkWallet({ session, http, urls }), { code: "challenge_mismatch" })
    assert.equal(state.signed.length, 0)
  })

  test("a challenge whose message lacks the nonce is not signed", async () => {
    const { session, state } = await linked()
    const http = server({ challenge: { nonce: "other", message } })
    await assert.rejects(linkWallet({ session, http, urls }), { code: "challenge_mismatch" })
    assert.equal(state.signed.length, 0)
  })

  test("rejection posts nothing", async () => {
    const { session, provider } = await linked()
    provider.handlers.personal_sign = () => { throw providerError(4001) }
    const http = server()
    await assert.rejects(linkWallet({ session, http, urls }), { code: "user_rejected" })
    assert.equal(http.calls.length, 1)
    assert.equal(session.state, "connected")
  })

  test("account switched during signing posts nothing", async () => {
    const { session, provider } = await linked()
    const pending = deferred()
    provider.handlers.personal_sign = () => pending.promise
    const http = server()
    const attempt = linkWallet({ session, http, urls })
    await tick()
    await tick()
    provider.emit("accountsChanged", [KEYS.two.address])
    await assert.rejects(attempt, { code: "stale" })
    pending.resolve("0xlate")
    await tick()
    assert.equal(http.calls.length, 1)
  })

  test("wrong chain does not block linking: EOA recovery is chain independent", async () => {
    const { session, provider } = await linked()
    provider.handlers.eth_chainId = () => "0x64"
    const wallet = await linkWallet({ session, http: server(), urls })
    assert.equal(wallet.address, address)
  })

  test("a server that confirms another address is not believed", async () => {
    const { session } = await linked()
    await assert.rejects(linkWallet({ session, http: server({ wallet: { id: 1, address: KEYS.two.address } }), urls }), { code: "link_mismatch" })
  })

  test("handoff returns deep links", async () => {
    const http = { post: async () => ({ url: "https://f.example/h/1", expires_at: "2026-11-09T12:00:00Z" }) }
    const handoff = await createHandoff({ http, url: "/wallet_handoffs" })
    assert.equal(handoff.expiresAt, "2026-11-09T12:00:00Z")
    assert.match(handoff.deepLinks.metamask, /f\.example\/h\/1$/)
  })
})

describe("walletconnect seam", () => {
  test("off without a project id, and never loads a package", async () => {
    assert.equal(walletConnectEnabled(""), false)
    assert.equal(walletConnectEnabled(null), false)
    assert.equal(walletConnectEnabled("abc"), true)
    await assert.rejects(loadWalletConnect("abc"), { code: "walletconnect_unavailable" })
  })
})

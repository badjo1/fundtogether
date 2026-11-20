// Singleton wallet session. Module state survives Turbo Drive visits, so provider listeners are
// attached here exactly once and Stimulus controllers only subscribe.
//
// Connection state is explicit. Whether a wallet is linked is derived per page by deriveStatus and
// never stored here: connected does not mean linked.
import { Discovery } from "wallet/discovery"
import { addChainParams, chainIdHex, parseChainId } from "wallet/chains"
import { detectEnvironment, noWalletCode } from "wallet/environment"
import { WalletError, normalizeError } from "wallet/errors"

const STORAGE_KEY = "ft.wallet"
const DISCOVERY_WINDOW_MS = 300
const ACCOUNTS_BANNER_MS = 60_000
const SIGNATURE_BANNERS = [[45_000, "open_wallet"], [120_000, "offer_reset"]]

const TRANSITIONS = {
  idle: ["discovering"],
  discovering: ["restoring", "disconnected", "no_wallet"],
  restoring: ["connected", "disconnected"],
  no_wallet: ["disconnected"],
  disconnected: ["requesting_accounts", "pairing", "no_wallet"],
  requesting_accounts: ["connected", "disconnected", "wallet_busy"],
  pairing: ["connected", "disconnected"],
  wallet_busy: ["requesting_accounts", "connected", "disconnected"],
  connected: ["switching_chain", "awaiting_signature", "submitting", "disconnected"],
  switching_chain: ["connected", "adding_chain", "disconnected"],
  adding_chain: ["switching_chain", "connected", "disconnected"],
  awaiting_signature: ["connected", "submitting", "stale", "wallet_busy", "disconnected"],
  submitting: ["connected", "disconnected"],
  stale: ["connected", "disconnected"]
}

export function deriveStatus({ state, address, chainId }, { linked = [], requiredChainId = null, requiresChain = false } = {}) {
  if (state !== "connected") return state
  const known = linked.map((entry) => String(entry).toLowerCase())
  if (!known.includes(address)) return known.length > 0 ? "address_mismatch" : "unlinked"
  if (requiresChain && chainId !== requiredChainId) return "wrong_network"
  return "ready"
}

function firstAddress(accounts) {
  const value = Array.isArray(accounts) ? accounts[0] : null
  return typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value) ? value.toLowerCase() : null
}

export class WalletSession {
  constructor({ window: win = globalThis.window, storage, userAgent, setTimer, clearTimer, discovery } = {}) {
    this.window = win
    this.storage = storage ?? safeLocalStorage(win)
    this.setTimer = setTimer || ((fn, ms) => setTimeout(fn, ms))
    this.clearTimer = clearTimer || ((id) => clearTimeout(id))
    this.environment = detectEnvironment(userAgent ?? win?.navigator?.userAgent ?? "")
    this.discovery = discovery || new Discovery(win)

    this.state = "idle"
    this.address = null
    this.chainId = null
    this.wallet = null
    this.banner = null
    this.notice = null
    this.userId = null
    this.subscribers = new Set()
    this.operationId = 0
    this.pending = null
    this.timers = new Set()
    this.attached = new WeakSet()
    this.removeProviderListeners = null

    this.handleAccountsChanged = this.handleAccountsChanged.bind(this)
    this.handleChainChanged = this.handleChainChanged.bind(this)
    this.handleDisconnect = this.handleDisconnect.bind(this)
    this.discovery.onChange(() => this.handleDiscoveryChange())
  }

  // --- Public read side

  snapshot() {
    return Object.freeze({
      state: this.state,
      address: this.address,
      chainId: this.chainId,
      wallet: this.wallet ? { name: this.wallet.name, icon: this.wallet.icon, rdns: this.wallet.rdns } : null,
      wallets: this.discovery.list().map(({ key, name, icon, rdns, legacy }) => ({ key, name, icon, rdns, legacy })),
      banner: this.banner,
      notice: this.notice,
      environment: this.environment
    })
  }

  get provider() {
    return this.wallet?.provider || null
  }

  subscribe(listener) {
    this.subscribers.add(listener)
    listener(this.snapshot())
    return () => this.subscribers.delete(listener)
  }

  // --- Lifecycle

  // Safe to call on every controller connect. A changed user on the same page lifetime (Turbo after
  // logout and login) drops the previous user's connection.
  init({ userId = null } = {}) {
    const user = userId === null || userId === undefined || userId === "" ? null : String(userId)
    const changed = user !== this.userId
    this.userId = user
    if (this.state === "idle") {
      this.go("discovering")
      this.discovery.start()
      this.watchVisibility()
      this.after(DISCOVERY_WINDOW_MS, () => this.finishDiscovery())
    } else if (changed && !["discovering"].includes(this.state)) {
      this.clearHint()
      if (this.state !== "disconnected" && this.state !== "no_wallet") this.dropConnection()
    }
  }

  finishDiscovery() {
    if (this.state !== "discovering") return
    const hint = this.readHint()
    if (hint && hint.userId === this.userId) {
      const remembered = this.discovery.findRemembered(hint.rdns)
      if (remembered) return this.restore(remembered)
    }
    if (hint && hint.userId !== this.userId) this.clearHint()
    if (this.discovery.list().length > 0) this.go("disconnected")
    else this.go("no_wallet")
  }

  // Silent: eth_accounts never prompts.
  async restore(entry) {
    const operation = this.nextOperation()
    this.go("restoring")
    try {
      const accounts = await entry.provider.request({ method: "eth_accounts" })
      const address = firstAddress(accounts)
      if (!this.isCurrent(operation)) return
      if (!address) {
        this.clearHint()
        return this.go("disconnected")
      }
      const chainId = parseChainId(await entry.provider.request({ method: "eth_chainId" }))
      if (!this.isCurrent(operation)) return
      this.adopt(entry, address, chainId)
    } catch {
      if (!this.isCurrent(operation)) return
      this.clearHint()
      this.go("disconnected")
    }
  }

  handleDiscoveryChange() {
    if (this.state === "no_wallet" && this.discovery.list().length > 0) this.go("disconnected")
    else this.publish()
  }

  // --- Connect

  async connect(walletKey = null) {
    if (this.state === "connected") return this.snapshot()
    if (this.state === "wallet_busy" && this.address) {
      this.go("connected")
      return this.snapshot()
    }
    if (!["disconnected", "wallet_busy", "no_wallet"].includes(this.state)) {
      throw new WalletError("wallet_action_pending")
    }

    const wallets = this.discovery.list()
    if (wallets.length === 0) throw new WalletError(noWalletCode(this.environment))
    const entry = walletKey ? this.discovery.find(walletKey) : wallets.length === 1 ? wallets[0] : null
    if (!entry) throw new WalletError("wallet_choice_required")

    if (this.state === "no_wallet") this.go("disconnected")
    const operation = this.nextOperation()
    this.setNotice(null)
    this.candidate = entry
    this.attach(entry)
    this.go("requesting_accounts")
    const timer = this.after(ACCOUNTS_BANNER_MS, () => this.isCurrent(operation) && this.setBanner("open_wallet"))

    try {
      const accounts = await entry.provider.request({ method: "eth_requestAccounts" })
      if (!this.isCurrent(operation)) return this.snapshot()
      const address = firstAddress(accounts)
      if (!address) throw new WalletError("unauthorized")
      const chainId = parseChainId(await entry.provider.request({ method: "eth_chainId" }))
      if (!this.isCurrent(operation)) return this.snapshot()
      this.adopt(entry, address, chainId)
      return this.snapshot()
    } catch (raw) {
      const error = normalizeError(raw)
      if (!this.isCurrent(operation)) throw error
      if (error.code === "wallet_busy") this.go("wallet_busy")
      else this.go("disconnected")
      this.setNotice(error)
      throw error
    } finally {
      this.cancelTimer(timer)
      this.setBanner(null)
    }
  }

  adopt(entry, address, chainId) {
    this.wallet = entry
    this.candidate = null
    this.address = address
    this.chainId = chainId
    this.attach(entry)
    this.writeHint({ kind: "injected", rdns: entry.rdns, userId: this.userId })
    this.go("connected")
  }

  disconnect() {
    this.clearHint()
    this.dropConnection()
  }

  logout() {
    this.disconnect()
  }

  dropConnection() {
    this.nextOperation()
    this.failPending(new WalletError("session_ended"))
    this.wallet = null
    this.candidate = null
    this.address = null
    this.chainId = null
    this.banner = null
    if (this.state !== "disconnected") this.go("disconnected", { force: true })
    this.detach()
  }

  // Abandons a request the wallet never answered. Wallet requests cannot be cancelled, so a late
  // answer is ignored through the operation id.
  resetPending() {
    this.nextOperation()
    this.setBanner(null)
    if (this.pending) this.failPending(new WalletError("user_rejected"))
    if (this.state === "requesting_accounts" || (this.state === "wallet_busy" && !this.address)) this.go("disconnected")
    else if (this.state === "awaiting_signature" || this.state === "wallet_busy" || this.state === "stale") this.go("connected")
  }

  acknowledgeStale() {
    if (this.state === "stale") this.go("connected")
  }

  // --- Chain

  async switchChain(chain) {
    this.requireConnected()
    const target = chain.chainId
    const operation = this.nextOperation()
    this.setNotice(null)
    this.go("switching_chain")
    try {
      try {
        await this.provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: chainIdHex(target) }] })
      } catch (raw) {
        const error = normalizeError(raw)
        if (error.code !== "chain_not_added") throw error
        if (!this.isCurrent(operation)) throw error
        this.go("adding_chain")
        await this.provider.request({ method: "wallet_addEthereumChain", params: [addChainParams(chain)] })
        if (!this.isCurrent(operation)) throw error
        this.go("switching_chain")
        // Some wallets switch as part of adding. Others need the explicit call.
        const afterAdd = parseChainId(await this.provider.request({ method: "eth_chainId" }))
        if (afterAdd !== target) {
          await this.provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: chainIdHex(target) }] })
        }
      }
      const current = parseChainId(await this.provider.request({ method: "eth_chainId" }))
      if (this.isCurrent(operation)) {
        this.chainId = current
        this.go("connected")
      }
      if (current !== target) throw new WalletError("chain_switch_failed")
      return this.snapshot()
    } catch (raw) {
      const normalized = normalizeError(raw)
      const error = ["user_rejected", "chain_switch_failed"].includes(normalized.code)
        ? normalized
        : new WalletError(this.state === "adding_chain" ? "chain_add_failed" : "chain_switch_failed", { cause: raw })
      if (this.isCurrent(operation) && ["switching_chain", "adding_chain"].includes(this.state)) this.go("connected")
      this.setNotice(error)
      throw error
    }
  }

  // --- Signing and sending

  requireConnected() {
    if (this.state === "stale") this.go("connected")
    if (this.state === "wallet_busy" && this.address) this.go("connected")
    if (this.state === "awaiting_signature" || this.state === "submitting" || this.state === "switching_chain" || this.state === "adding_chain") {
      throw new WalletError("wallet_action_pending")
    }
    if (this.state !== "connected") throw new WalletError("not_connected")
  }

  // Asks the wallet itself, right before an action, so UI state cannot vouch for it.
  async assertLive({ address = null, addresses = null, chainId = null } = {}) {
    this.requireConnected()
    const provider = this.provider
    const accounts = await provider.request({ method: "eth_accounts" }).catch((raw) => { throw normalizeError(raw) })
    const live = firstAddress(accounts)
    if (!live) throw new WalletError("not_connected")
    if (live !== this.address) {
      this.address = live
      this.publish()
    }
    const liveChain = parseChainId(await provider.request({ method: "eth_chainId" }).catch((raw) => { throw normalizeError(raw) }))
    if (liveChain !== this.chainId) {
      this.chainId = liveChain
      this.publish()
    }
    if (chainId !== null && liveChain !== chainId) throw new WalletError("wrong_network", { details: { expected: chainId, actual: liveChain } })
    if (address !== null && live !== address.toLowerCase()) throw new WalletError("wrong_account", { details: { expected: address, actual: live } })
    if (addresses !== null && !addresses.map((entry) => entry.toLowerCase()).includes(live)) {
      throw new WalletError("wrong_account", { details: { actual: live } })
    }
    return { address: live, chainId: liveChain }
  }

  // One wallet prompt at a time. If the account or chain changes while it is open, the promise
  // rejects with `stale` at once and any later answer is dropped, except through onLate: a late
  // transaction hash is real on-chain activity and the caller may want to report it.
  async request(method, params, { expected = {}, keepSubmitting = false, onLate = null } = {}) {
    const { address, chainId } = await this.assertLive(expected)
    this.requireConnected()

    const operation = this.nextOperation()
    this.setNotice(null)
    this.go("awaiting_signature")
    this.signatureSnapshot = { address, chainId, operation }
    const timers = SIGNATURE_BANNERS.map(([delay, banner]) => this.after(delay, () => this.isCurrent(operation) && this.setBanner(banner)))

    const interrupted = new Promise((_, reject) => { this.pending = { reject, operation } })
    const answer = Promise.resolve().then(() => this.provider.request({ method, params }))
    answer.then((result) => {
      if (!this.isCurrent(operation) && onLate) onLate(result)
    }, () => {})

    try {
      const result = await Promise.race([answer, interrupted])
      this.go(keepSubmitting ? "submitting" : "connected")
      return result
    } catch (raw) {
      const error = normalizeError(raw)
      if (this.isCurrent(operation) && this.state === "awaiting_signature") {
        this.go(error.code === "wallet_busy" ? "wallet_busy" : "connected")
        this.setNotice(error)
      }
      throw error
    } finally {
      timers.forEach((timer) => this.cancelTimer(timer))
      this.setBanner(null)
      this.pending = null
      this.signatureSnapshot = null
    }
  }

  // Wraps the POST after a signature. The state is presentation only; the server decides.
  async submit(work) {
    if (this.state !== "submitting") this.go("submitting")
    try {
      return await work()
    } finally {
      if (this.state === "submitting") this.go("connected")
    }
  }

  // --- Provider events

  handleAccountsChanged(accounts) {
    const address = firstAddress(accounts)
    switch (this.state) {
      case "connected":
      case "stale":
      case "switching_chain":
      case "adding_chain":
      case "submitting":
        if (!address) return this.lostAccounts()
        if (address !== this.address) {
          this.address = address
          this.publish()
        }
        break
      case "awaiting_signature":
        if (!address) return this.lostAccounts()
        if (address !== this.address) {
          this.address = address
          this.markStale()
        }
        break
      case "wallet_busy":
        if (address && this.candidate) this.finishBusy(this.candidate, address)
        else if (address) this.address = address
        break
      default:
        break
    }
  }

  async finishBusy(entry, address) {
    const operation = this.nextOperation()
    const chainId = parseChainId(await entry.provider.request({ method: "eth_chainId" }).catch(() => null))
    if (this.isCurrent(operation) && this.state === "wallet_busy") this.adopt(entry, address, chainId)
  }

  handleChainChanged(value) {
    const chainId = parseChainId(value)
    if (chainId === this.chainId) return
    if (this.state === "awaiting_signature") {
      this.chainId = chainId
      this.markStale()
    } else {
      this.chainId = chainId
      this.publish()
    }
  }

  handleDisconnect(error) {
    // 1013 is MetaMask reconnecting by itself, not an ended session.
    if (Number(error?.code) === 1013) return
    if (this.state === "disconnected" || this.state === "idle" || this.state === "discovering") return
    this.lostAccounts("session_ended")
  }

  lostAccounts(code = null) {
    this.dropConnection()
    if (code) this.setNotice(new WalletError(code))
  }

  markStale() {
    const error = new WalletError("stale")
    this.nextOperation()
    this.go("stale")
    this.setNotice(error)
    this.failPending(error)
  }

  failPending(error) {
    if (!this.pending) return
    const { reject } = this.pending
    this.pending = null
    reject(error)
  }

  // Exactly one set of listeners per provider, however many visits or controllers there are.
  attach(entry) {
    const provider = entry.provider
    if (this.attached.has(provider) || typeof provider.on !== "function") return
    this.detach()
    provider.on("accountsChanged", this.handleAccountsChanged)
    provider.on("chainChanged", this.handleChainChanged)
    provider.on("disconnect", this.handleDisconnect)
    this.attached.add(provider)
    this.removeProviderListeners = () => {
      const remove = provider.removeListener?.bind(provider)
      if (remove) {
        remove("accountsChanged", this.handleAccountsChanged)
        remove("chainChanged", this.handleChainChanged)
        remove("disconnect", this.handleDisconnect)
        this.attached.delete(provider)
      }
    }
  }

  detach() {
    if (this.removeProviderListeners) this.removeProviderListeners()
    this.removeProviderListeners = null
  }

  // Phones suspend the page while the wallet app is in front, so events can be missed.
  watchVisibility() {
    const doc = this.window?.document
    if (!doc?.addEventListener) return
    doc.addEventListener("visibilitychange", () => {
      if (doc.visibilityState === "visible" && this.state === "connected") this.refresh()
    })
  }

  async refresh() {
    const provider = this.provider
    if (!provider || this.state !== "connected") return
    try {
      const address = firstAddress(await provider.request({ method: "eth_accounts" }))
      const chainId = parseChainId(await provider.request({ method: "eth_chainId" }))
      if (this.state !== "connected") return
      if (!address) return this.lostAccounts()
      this.address = address
      this.chainId = chainId
      this.publish()
    } catch {
      // Keep the current state: the next action checks the wallet live anyway.
    }
  }

  // --- Internals

  go(next, { force = false } = {}) {
    if (!force && !TRANSITIONS[this.state]?.includes(next)) {
      throw new Error(`Illegal wallet transition: ${this.state} -> ${next}`)
    }
    this.state = next
    this.publish()
  }

  nextOperation() {
    this.operationId += 1
    return this.operationId
  }

  isCurrent(operation) {
    return this.operationId === operation
  }

  setBanner(banner) {
    if (this.banner === banner) return
    this.banner = banner
    this.publish()
  }

  setNotice(error) {
    this.notice = error ? error.toDetail() : null
    this.publish()
  }

  after(ms, fn) {
    const entry = { id: null }
    entry.id = this.setTimer(() => {
      this.timers.delete(entry)
      fn()
    }, ms)
    this.timers.add(entry)
    return entry
  }

  cancelTimer(entry) {
    if (!entry) return
    this.clearTimer(entry.id)
    this.timers.delete(entry)
  }

  publish() {
    const snapshot = this.snapshot()
    this.subscribers.forEach((listener) => listener(snapshot))
  }

  readHint() {
    try {
      const raw = this.storage?.getItem(STORAGE_KEY)
      return raw ? JSON.parse(raw) : null
    } catch {
      return null
    }
  }

  writeHint(hint) {
    try {
      this.storage?.setItem(STORAGE_KEY, JSON.stringify(hint))
    } catch {
      // Private mode: the user reconnects after a reload.
    }
  }

  clearHint() {
    try {
      this.storage?.removeItem(STORAGE_KEY)
    } catch {
      // Nothing was stored.
    }
  }
}

function safeLocalStorage(win) {
  try {
    return win?.localStorage ?? null
  } catch {
    return null
  }
}

let singleton = null

export function getSession() {
  if (!singleton) singleton = new WalletSession()
  return singleton
}

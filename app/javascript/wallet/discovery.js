// EIP-6963 discovery with a legacy window.ethereum fallback.
// Name, icon and rdns are self-attested: selection hints for display, never for trust.

const LEGACY_KEY = "legacy"

function safeIcon(icon) {
  return typeof icon === "string" && /^data:image\/[a-z+.-]+[;,]/i.test(icon) ? icon : null
}

function safeText(value, limit = 64) {
  return typeof value === "string" ? value.slice(0, limit) : ""
}

export class Discovery {
  constructor(target) {
    this.target = target
    this.announced = new Map()
    this.listeners = new Set()
    this.started = false
    this.handleAnnounce = this.handleAnnounce.bind(this)
    this.handleLegacyReady = () => this.notify()
  }

  // The listener goes on before the request is sent and stays for the page lifetime.
  start() {
    if (this.started || !this.target) return
    this.started = true
    this.target.addEventListener("eip6963:announceProvider", this.handleAnnounce)
    this.target.addEventListener("ethereum#initialized", this.handleLegacyReady)
    this.request()
  }

  request() {
    if (!this.target) return
    this.target.dispatchEvent(new this.target.Event("eip6963:requestProvider"))
  }

  handleAnnounce(event) {
    const { info, provider } = event.detail || {}
    if (!provider || typeof provider.request !== "function" || !info?.uuid) return
    const existing = this.announced.get(info.uuid)
    // A duplicate uuid must not swap the provider behind a wallet the user already sees.
    if (existing) return
    this.announced.set(info.uuid, {
      key: String(info.uuid),
      uuid: String(info.uuid),
      name: safeText(info.name) || "Browserwallet",
      icon: safeIcon(info.icon),
      rdns: safeText(info.rdns, 128) || null,
      legacy: false,
      provider
    })
    this.notify()
  }

  list() {
    if (this.announced.size > 0) return [...this.announced.values()]
    const legacy = this.target?.ethereum
    if (legacy && typeof legacy.request === "function") {
      return [{ key: LEGACY_KEY, uuid: null, name: "Browserwallet", icon: null, rdns: null, legacy: true, provider: legacy }]
    }
    return []
  }

  find(key) {
    return this.list().find((entry) => entry.key === key) || null
  }

  // After a reload uuids change, so a remembered wallet is found through its rdns.
  findRemembered(rdns) {
    const all = this.list()
    if (!rdns) return all.find((entry) => entry.legacy) || null
    return all.find((entry) => entry.rdns === rdns) || null
  }

  onChange(listener) {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  notify() {
    this.listeners.forEach((listener) => listener())
  }
}

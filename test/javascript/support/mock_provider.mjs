// Scriptable EIP-1193 provider for tests. A handler is a value, or a function of params.
export class MockProvider {
  constructor(handlers = {}) {
    this.handlers = handlers
    this.calls = []
    this.listeners = new Map()
  }

  async request({ method, params = [] }) {
    this.calls.push({ method, params })
    if (!Object.hasOwn(this.handlers, method)) throw Object.assign(new Error(`no handler: ${method}`), { code: 4200 })
    const handler = this.handlers[method]
    return typeof handler === "function" ? handler(params) : handler
  }

  on(event, listener) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set())
    this.listeners.get(event).add(listener)
  }

  removeListener(event, listener) {
    this.listeners.get(event)?.delete(listener)
  }

  emit(event, payload) {
    this.listeners.get(event)?.forEach((listener) => listener(payload))
  }

  listenerCount(event) {
    return this.listeners.get(event)?.size ?? 0
  }

  callsTo(method) {
    return this.calls.filter((call) => call.method === method)
  }
}

export function providerError(code, message = "provider error", extra = {}) {
  return Object.assign(new Error(message), { code, ...extra })
}

export function deferred() {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

export function fakeWindow({ userAgent = "Mozilla/5.0 (Macintosh)", ethereum = null } = {}) {
  const win = new EventTarget()
  win.Event = Event
  win.navigator = { userAgent }
  const store = new Map()
  win.localStorage = {
    getItem: (key) => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: (key) => store.delete(key)
  }
  if (ethereum) win.ethereum = ethereum
  return win
}

export function announce(win, provider, info = {}) {
  const detail = {
    info: { uuid: "uuid-1", name: "Testwallet", icon: "data:image/png;base64,AA==", rdns: "test.wallet", ...info },
    provider
  }
  win.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail }))
}

// Timers fire only when told to, so the tests are deterministic.
export function fakeTimers() {
  const pending = new Map()
  let id = 0
  return {
    setTimer: (fn, ms) => {
      id += 1
      pending.set(id, { fn, ms })
      return id
    },
    clearTimer: (timer) => pending.delete(timer),
    fire(ms) {
      for (const [key, timer] of [...pending]) {
        if (timer.ms <= ms) {
          pending.delete(key)
          timer.fn()
        }
      }
    },
    pendingCount: () => pending.size
  }
}

export function tick() {
  return new Promise((resolve) => setImmediate(resolve))
}

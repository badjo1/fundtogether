// JSON requests to our own server. Errors follow { error, message } from docs/ARCHITECTURE.md.
import { MESSAGES, WalletError } from "wallet/errors"

function csrfToken(doc) {
  return doc?.querySelector?.('meta[name="csrf-token"]')?.content || null
}

export function createHttp({ fetch: fetchFn = globalThis.fetch?.bind(globalThis), document: doc = globalThis.document } = {}) {
  async function send(method, url, body) {
    const headers = { Accept: "application/json" }
    if (body !== undefined) headers["Content-Type"] = "application/json"
    const token = csrfToken(doc)
    if (token) headers["X-CSRF-Token"] = token

    let response
    try {
      response = await fetchFn(url, {
        method,
        headers,
        credentials: "same-origin",
        body: body === undefined ? undefined : JSON.stringify(body)
      })
    } catch (cause) {
      throw new WalletError("server_unreachable", { cause })
    }

    // Following a redirect to the login page gives a 200 with HTML.
    const isJson = (response.headers?.get?.("content-type") || "").includes("json")
    if (response.status === 401 || (response.ok && !isJson && response.status !== 204)) {
      throw new WalletError("session_expired")
    }
    const payload = isJson ? await response.json().catch(() => null) : null
    if (!response.ok) {
      throw new WalletError("server_rejected", {
        message: typeof payload?.message === "string" ? payload.message : MESSAGES.server_rejected,
        details: { status: response.status, error: payload?.error ?? null }
      })
    }
    return payload
  }

  return {
    get: (url) => send("GET", url),
    post: (url, body = {}) => send("POST", url, body),
    patch: (url, body = {}) => send("PATCH", url, body),
    delete: (url) => send("DELETE", url)
  }
}

import { Controller } from "@hotwired/stimulus"
import { createHttp } from "wallet/http"
import { createHandoff, linkWallet } from "wallet/link"
import { getSession } from "wallet/session"
import { clearFlowUi, publishStep, resetOnTurboCache, runExclusive } from "wallet/ui"

export default class extends Controller {
  static targets = ["message"]
  static values = { challengesUrl: String, walletsUrl: String, handoffsUrl: String }

  connect() {
    this.stopCacheReset = resetOnTurboCache(this, () => clearFlowUi(this))
  }

  disconnect() {
    this.stopCacheReset?.()
  }

  link(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const wallet = await linkWallet({
        session: getSession(),
        http: createHttp(),
        urls: { challenges: this.challengesUrlValue, wallets: this.walletsUrlValue },
        onStep: (step) => publishStep(this, step)
      })
      publishStep(this, "linked", { wallet })
      return () => this.dispatch("linked", { detail: { wallet } })
    })
  }

  handoff(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const handoff = await createHandoff({ http: createHttp(), url: this.handoffsUrlValue })
      return () => this.dispatch("handoff", { detail: handoff })
    })
  }
}

import { Controller } from "@hotwired/stimulus"
import { normalizeChain } from "wallet/chains"
import { createHttp } from "wallet/http"
import { getSession } from "wallet/session"
import { clearFlowUi, publishStep, resetOnTurboCache, runExclusive } from "wallet/ui"

// viem loads only when a flow actually starts, so ordinary pages never fetch it.
export default class extends Controller {
  static targets = ["message"]
  static values = {
    url: String,
    chain: Object,
    createParams: Object,
    acknowledgeRisk: Boolean
  }

  connect() {
    this.stopCacheReset = resetOnTurboCache(this, () => clearFlowUi(this))
  }

  disconnect() {
    this.stopCacheReset?.()
  }

  deploy(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const { deploySafe } = await import("safe/flows")
      const createParams = Object.keys(this.createParamsValue).length > 0 ? this.createParamsValue : null
      const result = await deploySafe({
        session: getSession(),
        http: createHttp(),
        urls: { safe: this.urlValue },
        chain: normalizeChain(this.chainValue),
        createParams,
        intent: createParams ? { owners: createParams.owners, threshold: createParams.threshold } : null,
        acknowledgeRisk: this.acknowledgeRiskValue,
        onStep: (step, detail) => publishStep(this, step, detail),
        onHintFailed: (error) => this.dispatch("hint-failed", { detail: error.toDetail?.() })
      })
      publishStep(this, "deployed", { safeAddress: result.safeAddress, txHash: result.txHash })
      return () => this.dispatch("deployed", { detail: { safeAddress: result.safeAddress, txHash: result.txHash } })
    })
  }
}

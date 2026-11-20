import { Controller } from "@hotwired/stimulus"
import { normalizeChain } from "wallet/chains"
import { createHttp } from "wallet/http"
import { getSession } from "wallet/session"
import { clearFlowUi, fillFields, publishStep, resetOnTurboCache, runExclusive } from "wallet/ui"

export default class extends Controller {
  static targets = ["message", "field"]
  static values = {
    proposalUrl: String,
    executionUrl: String,
    syncUrl: String,
    chain: Object,
    safeAddress: String
  }

  connect() {
    this.stopCacheReset = resetOnTurboCache(this, () => this.clear())
  }

  disconnect() {
    this.stopCacheReset?.()
  }

  // Counts valid signatures against live owners, threshold and nonce.
  check(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const { executionReadiness } = await import("safe/flows")
      const readiness = await executionReadiness({ ...this.flowArgs(), onStep: (step) => publishStep(this, step) })
      fillFields(this.fieldTargets, readiness.display)
      publishStep(this, "checked", { readiness })
      this.element.dataset.executionReady = String(readiness.ready)
      return () => this.dispatch("checked", { detail: readiness })
    })
  }

  execute(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const { executeProposal } = await import("safe/flows")
      const result = await executeProposal({
        ...this.flowArgs(),
        onStep: (step, detail) => publishStep(this, step, detail),
        onHintFailed: (error) => this.dispatch("hint-failed", { detail: error.toDetail?.() })
      })
      publishStep(this, "executed", { txHash: result.txHash })
      return () => this.dispatch("executed", { detail: result })
    })
  }

  flowArgs() {
    return {
      session: getSession(),
      http: createHttp(),
      urls: { proposal: this.proposalUrlValue, execution: this.executionUrlValue, sync: this.syncUrlValue },
      chain: normalizeChain(this.chainValue),
      safeAddress: this.safeAddressValue
    }
  }

  clear() {
    clearFlowUi(this)
    fillFields(this.fieldTargets, {})
    delete this.element.dataset.executionReady
  }
}

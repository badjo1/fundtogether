import { Controller } from "@hotwired/stimulus"
import { normalizeChain } from "wallet/chains"
import { createHttp } from "wallet/http"
import { getSession } from "wallet/session"
import { clearFlowUi, fillFields, publishError, publishStep, resetOnTurboCache, runExclusive } from "wallet/ui"

export default class extends Controller {
  static targets = ["message", "field", "amount", "destination"]
  static values = {
    syncUrl: String,
    safeUrl: String,
    chain: Object,
    tokenAddress: String,
    safeAddress: String
  }

  connect() {
    this.stopCacheReset = resetOnTurboCache(this, () => this.clear())
    if (this.hasDestinationTarget) this.checkDestination()
  }

  disconnect() {
    this.stopCacheReset?.()
  }

  // On an RPC failure the balances stay empty and an error event fires. No figure silently shows zero.
  async refreshBalances(event) {
    event?.preventDefault?.()
    try {
      const { readBalances } = await import("safe/flows")
      const balances = await readBalances({ ...this.flowArgs() })
      fillFields(this.fieldTargets, {
        fundBalance: balances.fund?.formatted,
        walletBalance: balances.wallet?.formatted,
        gasBalance: balances.gas?.formatted,
        symbol: balances.fund?.symbol,
        gasSymbol: balances.gas?.symbol
      })
      this.dispatch("balances", { detail: balances })
    } catch (raw) {
      fillFields(this.fieldTargets, {})
      publishError(this, raw)
    }
  }

  // Before anyone types an amount: where this money would go, read from the chain and not from us.
  async checkDestination() {
    const element = this.destinationTarget
    try {
      const { checkDestination } = await import("safe/flows")
      const safe = await checkDestination({ ...this.flowArgs(), http: createHttp(), urls: { safe: this.safeUrlValue } })
      element.dataset.destinationState = "verified"
      fillFields(this.fieldTargets.filter((target) => target.dataset.field?.startsWith("destination")), {
        destinationAddress: safe.address,
        destinationOwners: safe.owners.join("\n"),
        destinationThreshold: `${safe.threshold} van de ${safe.owners.length}`,
        destinationStatus: "Zojuist gecontroleerd op de blockchain: een standaard Safe, zonder modules of guard."
      })
    } catch (raw) {
      element.dataset.destinationState = "refused"
      const detail = publishError(this, raw)
      fillFields(this.fieldTargets.filter((target) => target.dataset.field === "destinationStatus"), { destinationStatus: detail.message })
    }
  }

  contribute(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      const { contribute } = await import("safe/flows")
      const result = await contribute({
        ...this.flowArgs(),
        http: createHttp(),
        urls: { sync: this.syncUrlValue, safe: this.safeUrlValue || undefined },
        amount: this.hasAmountTarget ? this.amountTarget.value : "",
        onStep: (step, detail) => publishStep(this, step, detail),
        onHintFailed: (error) => this.dispatch("hint-failed", { detail: error.toDetail?.() })
      })
      publishStep(this, "contributed", result)
      if (this.hasAmountTarget) this.amountTarget.value = ""
      return () => this.dispatch("contributed", { detail: result })
    })
  }

  flowArgs() {
    return {
      session: getSession(),
      chain: normalizeChain(this.chainValue),
      tokenAddress: this.tokenAddressValue,
      safeAddress: this.safeAddressValue
    }
  }

  clear() {
    clearFlowUi(this)
    fillFields(this.fieldTargets, {})
    if (this.hasAmountTarget) this.amountTarget.value = ""
  }
}

import { Controller } from "@hotwired/stimulus"
import { normalizeChain } from "wallet/chains"
import { refuse } from "wallet/errors"
import { createHttp } from "wallet/http"
import { getSession } from "wallet/session"
import { clearFlowUi, fillFields, publishStep, resetOnTurboCache, runExclusive } from "wallet/ui"

export default class extends Controller {
  static targets = ["message", "field"]
  static values = {
    proposalUrl: String,
    signaturesUrl: String,
    chain: Object,
    safeAddress: String,
    linkedAddresses: Array
  }

  connect() {
    this.stopCacheReset = resetOnTurboCache(this, () => this.clear())
  }

  disconnect() {
    this.stopCacheReset?.()
  }

  // Steps 1 to 5: nothing is signed here. Show the result, then let the user press sign.
  review(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      this.reviewedHash = null
      const { reviewProposal } = await import("safe/flows")
      const { display } = await reviewProposal({ ...this.flowArgs(), onStep: (step) => publishStep(this, step) })
      this.reviewedHash = display.safeTxHash
      fillFields(this.fieldTargets, display)
      publishStep(this, "reviewed", { display })
      return () => this.dispatch("reviewed", { detail: { display } })
    })
  }

  // Refuses until a review has happened on this page, and re-verifies everything before the prompt.
  sign(event) {
    event?.preventDefault?.()
    return runExclusive(this, async () => {
      if (!this.reviewedHash) throw refuse("proposal_not_reviewed")
      const { signProposal } = await import("safe/flows")
      const result = await signProposal({
        ...this.flowArgs(),
        linked: this.linkedAddressesValue,
        reviewedHash: this.reviewedHash,
        onStep: (step, detail) => publishStep(this, step, detail)
      })
      publishStep(this, "signed", { signer: result.signer })
      return () => this.dispatch("signed", { detail: { proposal: result.proposal, signer: result.signer } })
    })
  }

  flowArgs() {
    return {
      session: getSession(),
      http: createHttp(),
      urls: { proposal: this.proposalUrlValue, signatures: this.signaturesUrlValue },
      chain: normalizeChain(this.chainValue),
      safeAddress: this.safeAddressValue
    }
  }

  clear() {
    this.reviewedHash = null
    clearFlowUi(this)
    fillFields(this.fieldTargets, {})
  }
}

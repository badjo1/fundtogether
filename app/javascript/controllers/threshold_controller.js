import { Controller } from "@hotwired/stimulus"

// Says a threshold choice in a sentence, and asks for the risk acknowledgement the server also demands.
// Used by the Safe setup (with owner checkboxes) and by the owner-change proposal forms (fixed count).
export default class extends Controller {
  static targets = ["owner", "select", "sentence", "riskAll", "riskOne", "ack", "ackRow", "submit", "noOwners"]
  static values = { count: Number, deploy: Object, stored: Boolean }

  connect() {
    this.touched = this.storedValue
    this.update()
  }

  update() {
    const count = this.ownerCount()
    this.syncOptions(count)
    const threshold = this.hasSelectTarget ? Number(this.selectTarget.value) : 0
    const risky = count > 1 && (threshold === 1 || threshold === count)

    if (this.hasSentenceTarget) this.sentenceTarget.textContent = this.sentence(threshold, count)
    if (this.hasRiskAllTarget) this.riskAllTarget.hidden = !(count > 1 && threshold === count)
    if (this.hasRiskOneTarget) this.riskOneTarget.hidden = !(count > 1 && threshold === 1)
    if (this.hasAckRowTarget) this.ackRowTarget.hidden = !risky
    if (this.hasNoOwnersTarget) this.noOwnersTarget.hidden = count > 0
    if (this.hasAckTarget && !risky) this.ackTarget.checked = false

    const acknowledged = !risky || (this.hasAckTarget && this.ackTarget.checked)
    const ready = count > 0 && threshold >= 1 && threshold <= count && acknowledged
    this.submitTargets.forEach((button) => { button.disabled = !ready })
    this.publishDeployParams(threshold, risky && acknowledged, ready)
  }

  ownerCount() {
    if (this.ownerTargets.length > 0) return this.ownerTargets.filter((box) => box.checked).length
    return this.countValue
  }

  syncOptions(count) {
    if (!this.hasSelectTarget || this.ownerTargets.length === 0) return
    const select = this.selectTarget
    const previous = Number(select.value)
    const fresh = Array.from({ length: Math.max(count, 1) }, (_, index) => {
      const option = document.createElement("option")
      option.value = String(index + 1)
      option.textContent = String(index + 1)
      return option
    })
    select.replaceChildren(...fresh)
    // Default to a majority: it survives one lost key and needs more than one person.
    const majority = Math.floor(count / 2) + 1
    select.value = String(previous >= 1 && previous <= count && this.touched ? previous : Math.max(majority, 1))
    select.disabled = count === 0
  }

  // The user chose: keep it while owners change, as far as it still fits.
  chosen() {
    this.touched = true
    this.update()
  }

  sentence(threshold, count) {
    if (count === 0) return "Kies eerst wie mag ondertekenen."
    if (count === 1) return "1 ondertekenaar beslist alleen."
    return `${threshold} van de ${count} moeten goedkeuren`
  }

  // The owners and threshold go to safe-deploy as its create-params value. Empty while not ready.
  publishDeployParams(threshold, acknowledged, ready) {
    const deployer = this.element.querySelector("[data-controller~='safe-deploy']")
    if (!deployer) return
    const owners = this.ownerTargets.filter((box) => box.checked).map((box) => box.value)
    const params = ready ? { ...this.deployValue, owners, threshold, acknowledge_risk: acknowledged } : {}
    deployer.dataset.safeDeployCreateParamsValue = JSON.stringify(params)
    deployer.dataset.safeDeployAcknowledgeRiskValue = String(acknowledged)
  }
}

import { Controller } from "@hotwired/stimulus"

const TERMINAL = new Set(["linked", "reviewed", "signed", "checked", "executed", "contributed", "deployed"])
const TX_HASH = /^0x[0-9a-fA-F]{64}$/

// Shows the progress of a wallet flow. Reacts to the step and error events of the flow controllers
// (docs/FRONTEND_CONTRACT.md) and holds no logic of its own: step targets carry their steps in data-steps.
export default class extends Controller {
  static targets = ["step", "reveal", "button", "txLink", "panel"]
  static values = { explorer: String, reloadDelay: { type: Number, default: 0 }, autoReload: { type: Number, default: 0 } }

  connect() {
    if (this.autoReloadValue > 0) this.timer = setTimeout(() => this.reload(), this.autoReloadValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // A change of wallet or network is what makes balances stale. Other wallet states are not.
  walletState({ detail }) {
    const key = `${detail.state}:${detail.address}:${detail.chainId}`
    if (key === this.walletKey) return
    this.walletKey = key
    if (["connected", "disconnected", "no_wallet"].includes(detail.state)) this.dispatch("wallet-changed")
  }

  step({ detail }) {
    const { step, txHash } = detail
    if (this.hasPanelTarget) this.panelTarget.hidden = false
    const current = this.stepTargets.findIndex((target) => target.dataset.steps.split(" ").includes(step))
    this.stepTargets.forEach((target, index) => {
      if (current < 0) return
      if (index < current) target.dataset.state = "done"
      else if (index === current) target.dataset.state = TERMINAL.has(step) ? "done" : "active"
      else target.dataset.state = "pending"
    })
    this.setBusy(!TERMINAL.has(step))
    if (txHash) this.showTransaction(txHash)
    this.revealTargets.forEach((target) => {
      if (target.dataset.on.split(" ").includes(step)) target.hidden = false
    })
  }

  error({ detail }) {
    this.stepTargets.forEach((target) => {
      if (target.dataset.state === "active") target.dataset.state = detail?.neutral ? "pending" : "failed"
    })
    this.setBusy(false)
    if (detail?.details?.txHash) this.showTransaction(detail.details.txHash)
  }

  // The page's truth comes from the server: reload instead of patching the DOM with a claim.
  reload() {
    setTimeout(() => window.Turbo.visit(window.location.href, { action: "replace" }), this.reloadDelayValue)
  }

  setBusy(busy) {
    this.buttonTargets.forEach((button) => { button.disabled = busy })
    this.element.setAttribute("aria-busy", String(busy))
  }

  showTransaction(txHash) {
    if (!TX_HASH.test(txHash) || !/^https:\/\//.test(this.explorerValue)) return
    this.txLinkTargets.forEach((link) => {
      link.href = `${this.explorerValue}/tx/${txHash}`
      link.hidden = false
    })
  }
}

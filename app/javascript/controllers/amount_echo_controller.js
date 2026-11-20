import { Controller } from "@hotwired/stimulus"

// Shows how an amount is read while it is typed: 1.000 could mean a thousand, and is refused.
export default class extends Controller {
  static targets = ["input", "output"]
  static values = { decimals: Number, symbol: String }

  async update() {
    const { echoAmount } = await import("safe/amounts")
    const { ok, text } = echoAmount(this.inputTarget.value, { decimals: this.decimalsValue, symbol: this.symbolValue })
    this.outputTarget.textContent = text
    this.outputTarget.dataset.tone = ok ? "neutral" : "refusal"
  }
}

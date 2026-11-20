import { Controller } from "@hotwired/stimulus"

// Shows the address field only when the payee is not a member.
export default class extends Controller {
  static targets = ["choice", "other"]

  connect() {
    this.update()
  }

  update() {
    this.otherTarget.hidden = this.choiceTarget.value !== "other"
  }
}

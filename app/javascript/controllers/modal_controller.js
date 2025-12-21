// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  open(event) {
    if (event) {
      event.preventDefault()
    }
    this.modalTarget.classList.remove("hidden")
  }

  close(event) {
    if (event) {
      event.preventDefault()
    }
    this.modalTarget.classList.add("hidden")
  }

  // Close modal when clicking outside (on backdrop)
  clickOutside(event) {
    if (event.target === event.currentTarget) {
      this.close(event)
    }
  }

  // Close modal on escape key
  closeWithKeyboard(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  connect() {
    // Add keyboard listener
    this.boundCloseWithKeyboard = this.closeWithKeyboard.bind(this)
    document.addEventListener("keydown", this.boundCloseWithKeyboard)
  }

  disconnect() {
    // Remove keyboard listener
    document.removeEventListener("keydown", this.boundCloseWithKeyboard)
  }
}

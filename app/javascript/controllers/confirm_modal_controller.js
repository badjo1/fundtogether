// app/javascript/controllers/confirm_modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["leaveModal", "deleteModal"]

  openLeave() {
    this.leaveModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  closeLeave() {
    this.leaveModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  openDelete() {
    this.deleteModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  closeDelete() {
    this.deleteModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Close modal on Escape key
  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.closeLeave()
      this.closeDelete()
    }
  }
}
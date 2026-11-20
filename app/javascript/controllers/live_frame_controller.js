import { Controller } from "@hotwired/stimulus"

// Wraps a lazy turbo-frame: optional periodic reload, and a Dutch error state when the frame itself
// cannot load. Chain outages are answered by the server inside the frame; this is for our own server.
export default class extends Controller {
  static targets = ["frame", "error"]
  static values = { interval: Number }

  connect() {
    if (this.intervalValue > 0) {
      this.timer = setInterval(() => {
        if (!document.hidden && this.hasFrameTarget && this.frameTarget.src) this.frameTarget.reload()
      }, this.intervalValue)
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }

  failed(event) {
    event.preventDefault()
    if (this.hasFrameTarget && this.hasErrorTarget) {
      this.frameTarget.replaceChildren(this.errorTarget.content.cloneNode(true))
    }
  }

  reload(event) {
    event?.preventDefault()
    if (this.hasFrameTarget && this.frameTarget.src) this.frameTarget.reload()
  }
}

// app/javascript/controllers/clipboard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]

  copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.value
    // currentTarget is null once the promise below resolves
    const button = event.currentTarget
    const label = button.querySelector("span")
    const original = label?.textContent

    navigator.clipboard.writeText(text).then(() => {
      if (label) label.textContent = "Gekopieerd!"
      button.classList.remove("bg-blue-600", "hover:bg-blue-700")
      button.classList.add("bg-green-600", "hover:bg-green-700")

      setTimeout(() => {
        if (label) label.textContent = original
        button.classList.remove("bg-green-600", "hover:bg-green-700")
        button.classList.add("bg-blue-600", "hover:bg-blue-700")
      }, 2000)
    }).catch(() => {
      if (label) label.textContent = "Kopieer handmatig"
    })
  }
}

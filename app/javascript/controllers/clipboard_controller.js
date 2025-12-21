// app/javascript/controllers/clipboard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]

  copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.value

    navigator.clipboard.writeText(text).then(() => {
      // Show success feedback
      const button = event.currentTarget
      const originalText = button.innerHTML

      button.innerHTML = `
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
        </svg>
        <span>Gekopieerd!</span>
      `
      button.classList.remove('bg-blue-600', 'hover:bg-blue-700')
      button.classList.add('bg-green-600', 'hover:bg-green-700')

      setTimeout(() => {
        button.innerHTML = originalText
        button.classList.remove('bg-green-600', 'hover:bg-green-700')
        button.classList.add('bg-blue-600', 'hover:bg-blue-700')
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
    })
  }
}

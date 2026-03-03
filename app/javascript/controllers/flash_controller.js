import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { duration: { type: Number, default: 2400 } }

  connect() {
    this.hideTimer = window.setTimeout(() => this.dismiss(), this.durationValue)
  }

  disconnect() {
    window.clearTimeout(this.hideTimer)
    window.clearTimeout(this.removeTimer)
  }

  dismiss() {
    this.element.classList.add("flash-wrap-hidden")
    this.removeTimer = window.setTimeout(() => {
      this.element.remove()
    }, 220)
  }
}

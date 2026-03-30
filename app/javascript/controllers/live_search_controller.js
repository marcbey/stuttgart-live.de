import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "clear"]
  static values = { delay: { type: Number, default: 180 } }

  connect() {
    this.toggleClear()
  }

  disconnect() {
    this.clearPendingSubmit()
  }

  queueSubmit() {
    this.toggleClear()
    this.clearPendingSubmit()
    this.submitTimeout = window.setTimeout(() => this.submit(), this.delayValue)
  }

  submitNow(event) {
    event.preventDefault()
    this.clearPendingSubmit()
    this.submit()
  }

  clear(event) {
    event.preventDefault()
    this.queryTarget.value = ""
    this.toggleClear()
    this.clearPendingSubmit()
    this.submit()
  }

  submit() {
    this.element.requestSubmit()
  }

  toggleClear() {
    if (!this.hasClearTarget) return

    this.clearTarget.classList.toggle("filter-date-clear-visible", this.queryTarget.value.length > 0)
  }

  clearPendingSubmit() {
    if (!this.submitTimeout) return

    window.clearTimeout(this.submitTimeout)
    this.submitTimeout = null
  }
}

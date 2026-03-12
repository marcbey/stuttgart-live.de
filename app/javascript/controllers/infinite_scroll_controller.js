import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["link"]
  static values = { url: String }

  connect() {
    this.loading = false
  }

  disconnect() {}

  async load(event) {
    event?.preventDefault()
    if (this.loading || !this.hasUrlValue || this.urlValue.length === 0) return

    this.loading = true
    const nextUrl = this.urlValue
    this.setPendingState(true)
    this.updateStatus("Weitere Events werden geladen …")

    try {
      const response = await fetch(nextUrl, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })

      if (!response.ok) {
        this.updateStatus("Weitere Events konnten nicht geladen werden.")
        return
      }

      const html = await response.text()
      Turbo.renderStreamMessage(html)
      this.updateStatus("Weitere Events wurden geladen.")
      this.urlValue = ""
    } catch (_error) {
      this.updateStatus("Weitere Events konnten nicht geladen werden.")
    } finally {
      this.loading = false
      this.setPendingState(false)
    }
  }

  setPendingState(pending) {
    if (!this.hasLinkTarget) return

    this.linkTarget.setAttribute("aria-disabled", pending ? "true" : "false")
    this.linkTarget.classList.toggle("is-loading", pending)
  }

  updateStatus(message) {
    const statusElement = document.getElementById("events-pagination-status")
    if (!statusElement) return

    statusElement.textContent = message
  }
}

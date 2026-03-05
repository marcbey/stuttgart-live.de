import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = [ "select" ]

  connect() {
    this.submitting = false
  }

  async change(event) {
    event.preventDefault()
    event.stopImmediatePropagation()
    if (this.submitting) return

    this.submitting = true
    const scrollY = window.scrollY
    const formData = new FormData(this.element)
    this.toggleSelect(true)

    try {
      const response = await fetch(this.element.action, {
        method: "PATCH",
        body: formData,
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      const stream = await response.text()
      if (!response.ok) throw new Error(`Status update failed (${response.status})`)

      Turbo.renderStreamMessage(stream)
    } catch (error) {
      console.error(error)
      this.toggleSelect(false)
    } finally {
      this.submitting = false
      window.scrollTo(0, scrollY)
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  toggleSelect(disabled) {
    if (!this.hasSelectTarget) return

    this.selectTarget.disabled = disabled
  }
}

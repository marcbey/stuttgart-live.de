import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    this.updateVisibility = this.updateVisibility.bind(this)
    window.addEventListener("scroll", this.updateVisibility, { passive: true })
    this.updateVisibility()
  }

  disconnect() {
    window.removeEventListener("scroll", this.updateVisibility)
  }

  scroll(event) {
    event.preventDefault()
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  updateVisibility() {
    if (!this.hasButtonTarget) return

    const shouldShow = window.scrollY > 640
    this.buttonTarget.hidden = !shouldShow
    this.buttonTarget.setAttribute("aria-hidden", shouldShow ? "false" : "true")
  }
}

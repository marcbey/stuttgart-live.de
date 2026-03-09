import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track", "previousButton", "nextButton" ]

  connect() {
    this.updateButtons = this.updateButtons.bind(this)
    this.trackTarget?.addEventListener("scroll", this.updateButtons, { passive: true })
    this.updateButtons()
  }

  disconnect() {
    this.trackTarget?.removeEventListener("scroll", this.updateButtons)
  }

  previous(event) {
    event.preventDefault()
    this.scrollByAmount(-1)
  }

  next(event) {
    event.preventDefault()
    this.scrollByAmount(1)
  }

  scrollByAmount(direction) {
    if (!this.hasTrackTarget) return

    const amount = Math.round(this.trackTarget.clientWidth * 0.82)
    this.trackTarget.scrollBy({ left: amount * direction, behavior: "smooth" })
  }

  updateButtons() {
    if (!this.hasTrackTarget) return

    const maxScrollLeft = this.trackTarget.scrollWidth - this.trackTarget.clientWidth
    const currentScroll = this.trackTarget.scrollLeft

    if (this.hasPreviousButtonTarget) {
      this.previousButtonTarget.disabled = currentScroll <= 4
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.disabled = currentScroll >= maxScrollLeft - 4
    }
  }
}

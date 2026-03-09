import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track", "previousButton", "nextButton" ]
  static values = {
    autoplay: { type: Boolean, default: false },
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.updateButtons = this.updateButtons.bind(this)
    this.trackTarget?.addEventListener("scroll", this.updateButtons, { passive: true })
    this.handleMouseEnter = () => this.stopAutoplay()
    this.handleMouseLeave = () => this.startAutoplay()
    this.element.addEventListener("mouseenter", this.handleMouseEnter)
    this.element.addEventListener("mouseleave", this.handleMouseLeave)
    this.updateButtons()
    this.startAutoplay()
  }

  disconnect() {
    this.trackTarget?.removeEventListener("scroll", this.updateButtons)
    this.element.removeEventListener("mouseenter", this.handleMouseEnter)
    this.element.removeEventListener("mouseleave", this.handleMouseLeave)
    this.stopAutoplay()
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

    const amount = this.scrollStep()
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

  startAutoplay() {
    if (!this.autoplayValue || !this.hasTrackTarget) return
    if (this.autoplayTimer) return

    this.autoplayTimer = window.setInterval(() => {
      const maxScrollLeft = this.trackTarget.scrollWidth - this.trackTarget.clientWidth
      const currentScroll = this.trackTarget.scrollLeft

      if (currentScroll >= maxScrollLeft - 4) {
        this.trackTarget.scrollTo({ left: 0, behavior: "smooth" })
      } else {
        this.scrollByAmount(1)
      }
    }, this.intervalValue)
  }

  scrollStep() {
    const firstCard = this.trackTarget.firstElementChild
    if (!(firstCard instanceof HTMLElement)) {
      return Math.round(this.trackTarget.clientWidth * 0.82)
    }

    const styles = window.getComputedStyle(this.trackTarget)
    const gap = Number.parseFloat(styles.columnGap || styles.gap || "0") || 0
    return Math.round(firstCard.getBoundingClientRect().width + gap)
  }

  stopAutoplay() {
    if (!this.autoplayTimer) return

    window.clearInterval(this.autoplayTimer)
    this.autoplayTimer = null
  }
}

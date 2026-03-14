import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track", "previousButton", "nextButton", "toggleButton" ]
  static values = {
    autoplay: { type: Boolean, default: false },
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.updateButtons = this.updateButtons.bind(this)
    this.handleFocusIn = this.handleFocusIn.bind(this)
    this.handleFocusOut = this.handleFocusOut.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.userPaused = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    this.trackTarget?.addEventListener("scroll", this.updateButtons, { passive: true })
    this.handleMouseEnter = () => this.stopAutoplay()
    this.handleMouseLeave = () => this.startAutoplay()
    this.element.addEventListener("mouseenter", this.handleMouseEnter)
    this.element.addEventListener("mouseleave", this.handleMouseLeave)
    this.element.addEventListener("focusin", this.handleFocusIn)
    this.element.addEventListener("focusout", this.handleFocusOut)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    this.updateButtons()
    this.updateToggleButton()
    this.startAutoplay()
  }

  disconnect() {
    this.trackTarget?.removeEventListener("scroll", this.updateButtons)
    this.element.removeEventListener("mouseenter", this.handleMouseEnter)
    this.element.removeEventListener("mouseleave", this.handleMouseLeave)
    this.element.removeEventListener("focusin", this.handleFocusIn)
    this.element.removeEventListener("focusout", this.handleFocusOut)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.stopAutoplay()
  }

  previous(event) {
    event.preventDefault()
    this.scrollByPage(-1)
  }

  next(event) {
    event.preventDefault()
    this.scrollByPage(1)
  }

  toggleAutoplay(event) {
    event.preventDefault()
    this.userPaused = !this.userPaused

    if (this.userPaused) {
      this.stopAutoplay()
    } else {
      this.startAutoplay()
    }

    this.updateToggleButton()
  }

  scrollByPage(direction) {
    const items = this.sliderItems()
    if (items.length === 0) return

    const currentIndex = this.leadingVisibleIndex(items)
    const pageSize = this.visibleItemCount(items)
    const targetIndex = this.clampIndex(currentIndex + (pageSize * direction), items)

    this.scrollToItem(items[targetIndex])
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
    if (this.userPaused || document.hidden) return
    if (this.autoplayTimer) return

    this.autoplayTimer = window.setInterval(() => {
      const maxScrollLeft = this.trackTarget.scrollWidth - this.trackTarget.clientWidth
      const currentScroll = this.trackTarget.scrollLeft

      if (currentScroll >= maxScrollLeft - 4) {
        this.trackTarget.scrollTo({ left: 0, behavior: "smooth" })
      } else {
        this.scrollBySingleItem()
      }
    }, this.intervalValue)
  }

  scrollBySingleItem() {
    const items = this.sliderItems()
    if (items.length === 0) return

    const currentIndex = this.leadingVisibleIndex(items)
    const targetIndex = this.clampIndex(currentIndex + 1, items)
    this.scrollToItem(items[targetIndex])
  }

  sliderItems() {
    if (!this.hasTrackTarget) return []

    return Array.from(this.trackTarget.children).filter((item) => item instanceof HTMLElement)
  }

  leadingVisibleIndex(items) {
    const currentScroll = this.trackTarget.scrollLeft

    for (let index = 0; index < items.length; index += 1) {
      const item = items[index]
      if ((item.offsetLeft + item.offsetWidth) > currentScroll + 4) {
        return index
      }
    }

    return Math.max(0, items.length - 1)
  }

  visibleItemCount(items) {
    const viewportStart = this.trackTarget.scrollLeft + 4
    const viewportEnd = viewportStart + this.trackTarget.clientWidth - 8
    let count = 0

    items.forEach((item) => {
      const itemStart = item.offsetLeft
      const itemEnd = itemStart + item.offsetWidth
      if (itemEnd > viewportStart && itemStart < viewportEnd) count += 1
    })

    return Math.max(count, 1)
  }

  clampIndex(index, items) {
    return Math.max(0, Math.min(index, items.length - 1))
  }

  scrollToItem(item) {
    if (!(item instanceof HTMLElement)) return

    this.trackTarget.scrollTo({ left: item.offsetLeft, behavior: "smooth" })
  }

  stopAutoplay() {
    if (!this.autoplayTimer) return

    window.clearInterval(this.autoplayTimer)
    this.autoplayTimer = null
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return

    this.toggleButtonTarget.textContent = this.userPaused ? "Animation starten" : "Animation pausieren"
    this.toggleButtonTarget.setAttribute("aria-pressed", this.userPaused ? "true" : "false")
  }

  handleFocusIn() {
    this.stopAutoplay()
  }

  handleFocusOut() {
    window.requestAnimationFrame(() => {
      if (this.element.contains(document.activeElement)) return
      this.startAutoplay()
    })
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stopAutoplay()
    } else {
      this.startAutoplay()
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    minDesktopWidth: { type: Number, default: 761 },
    mobileSearchOnlyEnterTrigger: { type: Number, default: 52 }
  }

  connect() {
    this.handleScroll = this.handleScroll.bind(this)
    this.handleResize = this.handleResize.bind(this)

    this.expandedHeight = this.measureExpandedHeight()

    window.addEventListener("scroll", this.handleScroll, { passive: true })
    window.addEventListener("resize", this.handleResize)

    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.handleScroll)
    window.removeEventListener("resize", this.handleResize)
  }

  handleScroll() {
    this.update()
  }

  handleResize() {
    if (!this.isDesktop()) {
      this.activateCompactMode()
      this.updateMobileSearchOnlyMode()
      return
    }

    this.deactivateMobileSearchOnlyMode()
    this.expandedHeight = this.measureExpandedHeight()
    this.update()
  }

  update() {
    if (!this.isDesktop()) {
      this.activateCompactMode()
      this.updateMobileSearchOnlyMode()
      return
    }

    this.deactivateMobileSearchOnlyMode()
    const isCompact = this.element.classList.contains("is-compact")
    const shouldCompact = isCompact ? window.scrollY > this.compactExitTrigger() : window.scrollY > this.compactEnterTrigger()

    if (shouldCompact) {
      this.element.classList.add("is-compact")
    } else {
      this.deactivateCompactMode()
    }
  }

  compactEnterTrigger() {
    return Math.max(96, Math.round(this.expandedHeight * 0.72))
  }

  compactExitTrigger() {
    return Math.max(72, Math.round(this.compactEnterTrigger() * 0.7))
  }

  measureExpandedHeight() {
    const wasCompact = this.element.classList.contains("is-compact")
    if (wasCompact) this.element.classList.remove("is-compact")

    const height = Math.ceil(this.element.getBoundingClientRect().height)

    if (wasCompact) this.element.classList.add("is-compact")

    return height
  }

  deactivateCompactMode() {
    if (!this.element.classList.contains("is-compact")) return

    this.element.classList.remove("is-compact")
    this.closeMenu()
  }

  activateCompactMode() {
    this.element.classList.add("is-compact")
  }

  updateMobileSearchOnlyMode() {
    if (this.element.classList.contains("is-mobile-search-only")) {
      if (window.scrollY <= 1) this.deactivateMobileSearchOnlyMode()
      return
    }

    if (window.scrollY > this.mobileSearchOnlyEnterTriggerValue) {
      this.activateMobileSearchOnlyMode()
    }
  }

  activateMobileSearchOnlyMode() {
    if (this.element.classList.contains("is-mobile-search-only")) return

    this.element.classList.add("is-mobile-search-only")
    this.closeMenu()
  }

  deactivateMobileSearchOnlyMode() {
    this.element.classList.remove("is-mobile-search-only")
  }

  closeMenu() {
    const button = this.element.querySelector("[data-mobile-nav-target='button']")
    const panel = this.element.querySelector("[data-mobile-nav-target='panel']")

    if (!button || !panel) return

    button.setAttribute("aria-expanded", "false")
    button.setAttribute("aria-label", "Navigation öffnen")
    panel.dataset.open = "false"
  }

  isDesktop() {
    return window.innerWidth >= this.minDesktopWidthValue
  }
}

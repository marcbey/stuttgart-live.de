import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    minDesktopWidth: { type: Number, default: 761 }
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
      this.deactivateCompactMode()
      return
    }

    this.expandedHeight = this.measureExpandedHeight()
    this.update()
  }

  update() {
    if (!this.isDesktop()) {
      this.deactivateCompactMode()
      return
    }

    const shouldCompact = window.scrollY > this.compactTrigger()

    if (shouldCompact) {
      this.element.classList.add("is-compact")
    } else {
      this.deactivateCompactMode()
    }
  }

  compactTrigger() {
    return Math.max(96, Math.round(this.expandedHeight * 0.72))
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

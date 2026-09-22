import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "button", "checkbox"]

  connect() {
    this.update = this.update.bind(this)
    this.sidebar = this.element
      .closest(".design-detail-preview-content")
      ?.querySelector(".design-detail-preview-related--desktop-side")

    this.update()
    window.requestAnimationFrame(this.update)
    window.addEventListener("resize", this.update)
    document.fonts?.ready.then(this.update)

    if (this.sidebar && "ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(this.update)
      this.resizeObserver.observe(this.sidebar)
    }
  }

  disconnect() {
    window.removeEventListener("resize", this.update)
    this.resizeObserver?.disconnect()
  }

  toggle() {
    this.buttonTarget.setAttribute("aria-expanded", this.checkboxTarget.checked.toString())
  }

  update() {
    if (!this.hasBodyTarget || !this.hasButtonTarget) return

    const wasChecked = this.hasCheckboxTarget ? this.checkboxTarget.checked : false

    this.element.classList.add("design-detail-preview-description-toggle--needs-more")
    this.buttonTarget.hidden = false
    if (this.hasCheckboxTarget) this.checkboxTarget.checked = false
    this.applySidebarHeightLimit()

    const needsToggle = this.bodyTarget.scrollHeight > this.bodyTarget.clientHeight + 2

    this.element.classList.toggle("design-detail-preview-description-toggle--needs-more", needsToggle)
    this.buttonTarget.hidden = !needsToggle

    if (this.hasCheckboxTarget) {
      this.checkboxTarget.checked = needsToggle && wasChecked
      this.toggle()
    }
  }

  applySidebarHeightLimit() {
    this.element.style.removeProperty("--description-collapsed-height")
    if (!window.matchMedia("(min-width: 48rem)").matches || !this.sidebar) return

    const sidebarBottom = this.sidebar.getBoundingClientRect().bottom
    const toggleTop = this.element.getBoundingClientRect().top
    const buttonHeight = this.buttonTarget.getBoundingClientRect().height
    const gap = Number.parseFloat(window.getComputedStyle(this.element).rowGap) || 0
    const availableHeight = sidebarBottom - toggleTop - buttonHeight - gap

    if (availableHeight > 0) {
      this.element.style.setProperty("--description-collapsed-height", `${Math.max(192, availableHeight)}px`)
    }
  }
}

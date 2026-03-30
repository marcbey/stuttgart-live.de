import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "panel" ]
  static values = {
    desktopMinWidth: { type: Number, default: 761 }
  }

  connect() {
    this.close = this.close.bind(this)
    this.handleResize = this.handleResize.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    window.addEventListener("resize", this.handleResize)
    this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener("resize", this.handleResize)
  }

  toggle() {
    if (this.isDesktop()) return

    this.buttonTarget.getAttribute("aria-expanded") === "true" ? this.close() : this.open()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", "Navigation schließen")
    this.panelTarget.dataset.open = "true"
  }

  close() {
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", "Navigation öffnen")
    this.panelTarget.dataset.open = "false"
  }

  handleResize() {
    if (this.isDesktop()) this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  isDesktop() {
    return window.innerWidth >= this.desktopMinWidthValue
  }
}

import { Controller } from "@hotwired/stimulus"

const OVERLAY_OPENED_EVENT = "design-preview:overlay-opened"
const OVERLAY_SOURCE = "menu"

export default class extends Controller {
  static targets = [ "button", "panel" ]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleDocumentClick = this.handleDocumentClick.bind(this)
    this.handleOverlayOpened = this.handleOverlayOpened.bind(this)

    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("click", this.handleDocumentClick)
    window.addEventListener(OVERLAY_OPENED_EVENT, this.handleOverlayOpened)
    this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("click", this.handleDocumentClick)
    window.removeEventListener(OVERLAY_OPENED_EVENT, this.handleOverlayOpened)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    this.isOpen() ? this.close() : this.open()
  }

  open() {
    this.announceOpen()
    this.panelTarget.hidden = false
    this.panelTarget.dataset.open = "true"
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-expanded", "true")
      button.setAttribute("aria-label", "Menü schließen")
      button.classList.add("is-open")
    })
  }

  close() {
    this.panelTarget.hidden = true
    this.panelTarget.dataset.open = "false"
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-expanded", "false")
      button.setAttribute("aria-label", "Menü öffnen")
      button.classList.remove("is-open")
    })
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  handleDocumentClick(event) {
    if (!this.isOpen() || this.element.contains(event.target)) return

    this.close()
  }

  handleOverlayOpened(event) {
    if (event.detail?.source === OVERLAY_SOURCE) return

    this.close()
  }

  announceOpen() {
    window.dispatchEvent(new CustomEvent(OVERLAY_OPENED_EVENT, {
      detail: { source: OVERLAY_SOURCE }
    }))
  }

  isOpen() {
    return this.hasPanelTarget && this.panelTarget.dataset.open === "true"
  }
}

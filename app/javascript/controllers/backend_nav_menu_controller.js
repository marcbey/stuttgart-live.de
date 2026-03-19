import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "panel" ]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("click", this.handleClickOutside)
    this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("click", this.handleClickOutside)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    this.isOpen() ? this.close() : this.open()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", "Backend-Menü schließen")
    this.panelTarget.hidden = false
    this.panelTarget.dataset.open = "true"
  }

  close() {
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", "Backend-Menü öffnen")
    this.panelTarget.hidden = true
    this.panelTarget.dataset.open = "false"
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  isOpen() {
    return this.buttonTarget.getAttribute("aria-expanded") === "true"
  }
}

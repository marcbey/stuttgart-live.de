import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]
  static values = { key: { type: String, default: "backend-events-next-event-enabled" } }

  connect() {
    this.pendingManualSubmit = false
    this.ensureDefaultSetting()
    this.applyToggleState()
  }

  markManualSubmit() {
    this.pendingManualSubmit = true
  }

  toggleChanged() {
    if (!this.hasToggleTarget) return

    window.localStorage.setItem(this.keyValue, this.toggleTarget.checked ? "1" : "0")
  }

  handleSubmitEnd(event) {
    if (!this.pendingManualSubmit) return

    this.pendingManualSubmit = false
    if (!event.detail.success || !this.nextEventEnabled()) return

    const links = Array.from(document.querySelectorAll(".event-link"))
    if (links.length === 0) return

    const activeLink = document.querySelector(".event-list-item-active .event-link")
    if (!activeLink) return

    const currentIndex = links.indexOf(activeLink)
    if (currentIndex < 0 || currentIndex >= links.length - 1) return

    const nextLink = links[currentIndex + 1]
    if (nextLink) nextLink.click()
  }

  ensureDefaultSetting() {
    if (window.localStorage.getItem(this.keyValue) !== null) return

    window.localStorage.setItem(this.keyValue, "1")
  }

  applyToggleState() {
    if (!this.hasToggleTarget) return

    this.toggleTarget.checked = this.nextEventEnabled()
  }

  nextEventEnabled() {
    return window.localStorage.getItem(this.keyValue) !== "0"
  }
}

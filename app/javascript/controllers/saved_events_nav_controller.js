import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, savedEventSlugs } from "../lib/saved_events_storage"

export default class extends Controller {
  static targets = [ "link", "count" ]

  connect() {
    this.handleSavedEventsChanged = this.render.bind(this)
    this.handleStorage = this.handleStorage.bind(this)

    window.addEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.addEventListener("storage", this.handleStorage)
    this.render()
  }

  disconnect() {
    window.removeEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.removeEventListener("storage", this.handleStorage)
  }

  render() {
    const count = savedEventSlugs().length
    this.element.classList.toggle("has-saved-events-link", count > 0)

    this.linkTargets.forEach((link) => {
      link.hidden = false
      link.setAttribute("aria-label", count === 1 ? "1 gemerktes Event anzeigen" : `${count} gemerkte Events anzeigen`)
    })

    this.countTargets.forEach((countTarget) => {
      countTarget.textContent = count.toString()
    })
  }

  handleStorage(event) {
    if (event.key && event.key !== STORAGE_KEY) return

    this.render()
  }
}

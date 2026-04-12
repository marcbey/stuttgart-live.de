import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, savedEventSlugs } from "../lib/saved_events_storage"

export default class extends Controller {
  static targets = [ "link" ]

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
    const visible = savedEventSlugs().length > 0
    this.element.classList.toggle("has-saved-events-link", visible)

    if (this.hasLinkTarget) {
      this.linkTarget.hidden = !visible
    }
  }

  handleStorage(event) {
    if (event.key && event.key !== STORAGE_KEY) return

    this.render()
  }
}

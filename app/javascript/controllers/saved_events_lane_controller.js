import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, savedEventSlugs } from "../lib/saved_events_storage"

export default class extends Controller {
  static values = {
    emptyMessage: String,
    emptyTitle: String,
    showEmpty: { type: Boolean, default: false },
    unavailableMessage: String,
    unavailableTitle: String,
    url: String
  }

  connect() {
    this.requestId = 0
    this.handleSavedEventsChanged = this.load.bind(this)
    this.handleStorage = this.handleStorage.bind(this)

    window.addEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.addEventListener("storage", this.handleStorage)
    this.load()
  }

  disconnect() {
    window.removeEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.removeEventListener("storage", this.handleStorage)
    this.abortPendingRequest()
  }

  async load() {
    if (!this.hasUrlValue) {
      this.clear()
      return
    }

    const slugs = savedEventSlugs()
    if (slugs.length === 0) {
      this.renderEmpty()
      return
    }

    const requestId = ++this.requestId
    const url = new URL(this.urlValue, window.location.origin)
    const currentUrl = new URL(window.location.href)

    for (const name of [ "event_date", "filter" ]) {
      const value = currentUrl.searchParams.get(name)
      if (value) url.searchParams.set(name, value)
    }

    slugs.forEach((slug) => url.searchParams.append("slugs[]", slug))

    this.abortPendingRequest()
    const abortController = new AbortController()
    this.abortController = abortController

    try {
      const response = await fetch(url, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: abortController.signal
      })

      const html = await response.text()
      if (requestId !== this.requestId) return
      if (!response.ok) throw new Error(`Saved lane request failed (${response.status})`)

      if (html.trim().length === 0) {
        this.renderUnavailable()
        return
      }

      this.element.innerHTML = html
      this.element.hidden = false
    } catch (error) {
      if (error.name === "AbortError") return
      console.error(error)
    } finally {
      if (this.abortController === abortController) {
        this.abortController = null
      }
    }
  }

  handleStorage(event) {
    if (event.key && event.key !== STORAGE_KEY) return
    this.load()
  }

  clear() {
    this.abortPendingRequest()
    this.element.innerHTML = ""
    this.element.hidden = true
  }

  renderEmpty() {
    this.renderMessage({
      title: this.emptyTitleValue || "Du hast noch keine Events gemerkt.",
      message: this.emptyMessageValue || "Tippe bei einem Event auf das Herz, dann findest du es hier wieder."
    })
  }

  renderUnavailable() {
    this.renderMessage({
      title: this.unavailableTitleValue || "Deine gemerkten Events sind aktuell nicht mehr verfügbar.",
      message: this.unavailableMessageValue || "Manche Termine sind vielleicht vorbei oder nicht mehr öffentlich sichtbar."
    })
  }

  renderMessage({ title, message }) {
    this.abortPendingRequest()

    if (!this.showEmptyValue) {
      this.clear()
      return
    }

    this.element.replaceChildren(this.emptyStateElement(title, message))
    this.element.hidden = false
  }

  emptyStateElement(title, message) {
    const wrapper = document.createElement("div")
    wrapper.className = "search-results-empty saved-events-empty"

    const heading = document.createElement("h2")
    heading.textContent = title
    wrapper.appendChild(heading)

    const copy = document.createElement("p")
    copy.textContent = message
    wrapper.appendChild(copy)

    return wrapper
  }

  abortPendingRequest() {
    if (!this.abortController) return

    this.abortController.abort()
    this.abortController = null
  }
}

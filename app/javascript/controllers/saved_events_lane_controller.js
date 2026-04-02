import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, savedEventSlugs } from "../lib/saved_events_storage"

export default class extends Controller {
  static values = { url: String }

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
      this.clear()
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
        this.clear()
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

  abortPendingRequest() {
    if (!this.abortController) return

    this.abortController.abort()
    this.abortController = null
  }
}

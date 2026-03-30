import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hidden", "panel", "results", "status"]
  static values = {
    url: String,
    debounce: { type: Number, default: 180 },
    minimumLength: { type: Number, default: 2 }
  }

  connect() {
    this.abortController = null
    this.searchTimeout = null
    this.results = []
    this.activeIndex = -1
    this.boundHandlePointerDown = this.handlePointerDown.bind(this)

    document.addEventListener("pointerdown", this.boundHandlePointerDown)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.boundHandlePointerDown)
    this.abortPendingRequest()
    this.clearScheduledSearch()
  }

  open() {
    if (!this.hasEnoughCharacters) {
      this.close()
      return
    }

    this.scheduleSearch()
  }

  search() {
    this.hiddenTarget.value = ""
    this.activeIndex = -1

    if (!this.query.present) {
      this.close()
      return
    }

    if (!this.hasEnoughCharacters) {
      this.renderHint(`Mindestens ${this.minimumLengthValue} Zeichen eingeben`)
      return
    }

    this.scheduleSearch()
  }

  keydown(event) {
    if (event.key === "ArrowDown") {
      if (this.results.length === 0) return
      event.preventDefault()
      this.setActiveIndex(this.activeIndex + 1)
      return
    }

    if (event.key === "ArrowUp") {
      if (this.results.length === 0) return
      event.preventDefault()
      this.setActiveIndex(this.activeIndex <= 0 ? this.results.length - 1 : this.activeIndex - 1)
      return
    }

    if (event.key === "Enter") {
      if (this.activeIndex < 0 || this.results.length === 0) return
      event.preventDefault()
      this.applySelection(this.results[this.activeIndex])
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  select(event) {
    event.preventDefault()
    const index = Number(event.currentTarget.dataset.index)
    const result = this.results[index]
    if (!result) return

    this.applySelection(result)
  }

  async fetchResults() {
    const requestUrl = this.buildRequestUrl()
    if (!requestUrl) {
      this.close()
      return
    }

    this.abortPendingRequest()
    this.abortController = new AbortController()
    const currentAbortController = this.abortController

    try {
      const response = await fetch(requestUrl, {
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: currentAbortController.signal
      })

      if (!response.ok) {
        throw new Error(`Venue search failed with status ${response.status}`)
      }

      this.results = await response.json()
      this.activeIndex = this.results.length > 0 ? 0 : -1
      this.renderResults()
    } catch (error) {
      if (error.name === "AbortError") return

      this.renderHint("Venue-Suche ist gerade nicht verfügbar")
    } finally {
      if (this.abortController === currentAbortController) {
        this.abortController = null
      }
    }
  }

  handlePointerDown(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  clearScheduledSearch() {
    if (!this.searchTimeout) return

    window.clearTimeout(this.searchTimeout)
    this.searchTimeout = null
  }

  abortPendingRequest() {
    if (!this.abortController) return

    this.abortController.abort()
    this.abortController = null
  }

  scheduleSearch() {
    this.clearScheduledSearch()
    this.searchTimeout = window.setTimeout(() => this.fetchResults(), this.debounceValue)
  }

  applySelection(result) {
    this.hiddenTarget.value = result.id
    this.inputTarget.value = result.name
    this.results = []
    this.activeIndex = -1
    this.close()
  }

  renderResults() {
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")

    if (this.results.length === 0) {
      this.renderHint("Keine Treffer. Neue Venue wird beim Speichern angelegt.")
      return
    }

    const itemsHtml = this.results.map((result, index) => {
      const address = result.address ? `<span class="venue-autocomplete-item-meta">${this.escapeHtml(result.address)}</span>` : ""
      const activeClass = index === this.activeIndex ? " is-active" : ""

      return `
        <button type="button"
                class="venue-autocomplete-item${activeClass}"
                data-index="${index}"
                data-action="click->venue-autocomplete#select">
          <span class="venue-autocomplete-item-name">${this.escapeHtml(result.name)}</span>
          ${address}
        </button>
      `
    }).join("")

    this.resultsTarget.innerHTML = itemsHtml
    this.statusTarget.textContent = `${this.results.length} Venue-Vorschläge verfügbar`
  }

  renderHint(message) {
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.resultsTarget.innerHTML = `<div class="venue-autocomplete-empty">${this.escapeHtml(message)}</div>`
    this.statusTarget.textContent = message
  }

  close() {
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.panelTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  setActiveIndex(index) {
    if (this.results.length === 0) {
      this.activeIndex = -1
      return
    }

    if (index < 0) {
      this.activeIndex = this.results.length - 1
    } else {
      this.activeIndex = index % this.results.length
    }

    this.renderResults()
  }

  buildRequestUrl() {
    if (!this.hasEnoughCharacters) return null

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", this.query.value)
    return url.toString()
  }

  escapeHtml(value) {
    return value
      .toString()
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;")
  }

  get query() {
    const value = this.inputTarget.value.toString().trim()

    return {
      value,
      present: value.length > 0
    }
  }

  get hasEnoughCharacters() {
    return this.query.value.length >= this.minimumLengthValue
  }
}

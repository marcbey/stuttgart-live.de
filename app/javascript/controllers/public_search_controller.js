import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "panel", "results", "idleTemplate"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 180 }
  }

  connect() {
    this.abortController = null
    this.lastRequestKey = null
    this.searchTimeout = null
    this.boundHandlePointerDown = this.handlePointerDown.bind(this)
    this.boundHandleDocumentKeydown = this.handleDocumentKeydown.bind(this)

    document.addEventListener("pointerdown", this.boundHandlePointerDown)
    document.addEventListener("keydown", this.boundHandleDocumentKeydown)
    this.syncControls()
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.boundHandlePointerDown)
    document.removeEventListener("keydown", this.boundHandleDocumentKeydown)
    this.abortPendingRequest()
    this.clearScheduledSearch()
  }

  open() {
    this.showPanel()

    if (this.query.present) {
      this.scheduleSearch()
    } else {
      this.loadIdleResults()
    }
  }

  search() {
    this.syncControls()
    this.showPanel()

    if (!this.query.present) {
      this.abortPendingRequest()
      this.clearScheduledSearch()
      this.loadIdleResults()
      return
    }

    this.scheduleSearch()
  }

  clear(event) {
    event.preventDefault()

    this.inputTarget.value = ""
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.syncControls()
    this.loadIdleResults()
    this.showPanel()
    this.inputTarget.focus()

    if (this.currentLocationHasQuery()) {
      this.element.requestSubmit()
    }
  }

  close() {
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.panelTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  handlePointerDown(event) {
    if (this.element.contains(event.target)) {
      return
    }

    this.close()
  }

  handleDocumentKeydown(event) {
    if (event.defaultPrevented) {
      return
    }

    if (event.key.toLowerCase() !== "s") {
      return
    }

    if (event.ctrlKey || event.metaKey || event.altKey) {
      return
    }

    if (this.isTypingContext(event.target)) {
      return
    }

    event.preventDefault()
    this.inputTarget.focus()
    this.open()
  }

  handleInputKeydown(event) {
    if (event.key === "ArrowDown") {
      const firstResult = this.resultElements[0]
      if (!firstResult) {
        return
      }

      event.preventDefault()
      firstResult.focus()
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      this.inputTarget.blur()
    }
  }

  handleResultKeydown(event) {
    const currentIndex = this.resultElements.indexOf(event.currentTarget)
    if (currentIndex === -1) {
      return
    }

    if (event.key === "ArrowDown") {
      const nextResult = this.resultElements[currentIndex + 1]
      if (!nextResult) {
        return
      }

      event.preventDefault()
      nextResult.focus()
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()

      const previousResult = this.resultElements[currentIndex - 1]
      if (previousResult) {
        previousResult.focus()
      } else {
        this.inputTarget.focus()
      }
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      this.inputTarget.focus()
    }
  }

  applySuggestion(event) {
    event.preventDefault()

    this.inputTarget.value = event.currentTarget.dataset.query || ""
    this.syncControls()

    if (event.currentTarget.dataset.submit === "true") {
      this.close()
      this.element.requestSubmit()
      return
    }

    this.showPanel()
    this.inputTarget.focus()
    this.search()
  }

  async fetchResults() {
    const requestUrl = this.buildRequestUrl()
    const requestKey = this.buildRequestKey()

    if (requestKey === this.lastRequestKey) {
      return
    }

    this.abortPendingRequest()
    this.abortController = new AbortController()
    const currentAbortController = this.abortController

    try {
      const response = await fetch(requestUrl, {
        headers: { Accept: "text/html" },
        signal: this.abortController.signal
      })

      if (!response.ok) {
        throw new Error(`Search request failed with status ${response.status}`)
      }

      this.resultsTarget.innerHTML = await response.text()
      this.lastRequestKey = requestKey
    } catch (error) {
      if (error.name === "AbortError") {
        return
      }
    } finally {
      if (this.abortController === currentAbortController) {
        this.abortController = null
      }
    }
  }

  scheduleSearch() {
    this.clearScheduledSearch()
    this.searchTimeout = window.setTimeout(() => this.fetchResults(), this.debounceValue)
  }

  renderIdleState() {
    this.resultsTarget.innerHTML = this.idleTemplateTarget.innerHTML
    this.lastRequestKey = null
  }

  loadIdleResults() {
    this.renderIdleState()
    this.fetchResults()
  }

  showPanel() {
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  syncControls() {
    this.clearTarget.classList.toggle("public-search-clear-visible", this.query.hasValue)
  }

  buildRequestUrl() {
    const url = new URL(this.searchUrlValue, window.location.origin)
    const params = new URLSearchParams(new FormData(this.element))

    params.set("q", this.query.value)
    params.delete("page")
    url.search = params.toString()

    return url.toString()
  }

  buildRequestKey() {
    const url = new URL(this.searchUrlValue, window.location.origin)
    const params = new URLSearchParams(new FormData(this.element))

    params.set("q", this.query.normalizedValue)
    params.delete("page")
    url.search = params.toString()

    return url.toString()
  }

  abortPendingRequest() {
    this.abortController?.abort()
    this.abortController = null
  }

  clearScheduledSearch() {
    window.clearTimeout(this.searchTimeout)
    this.searchTimeout = null
  }

  currentLocationHasQuery() {
    return new URL(window.location.href).searchParams.has("q")
  }

  isTypingContext(target) {
    if (!(target instanceof HTMLElement)) {
      return false
    }

    if (target.isContentEditable) {
      return true
    }

    const tagName = target.tagName
    return tagName === "INPUT" || tagName === "TEXTAREA" || tagName === "SELECT"
  }

  get resultElements() {
    return Array.from(this.resultsTarget.querySelectorAll("[data-public-search-result='true'], a.public-search-result"))
  }

  get query() {
    const value = this.inputTarget.value.toString().trim()
    const normalizedValue = this.normalizeQueryValue(value)

    return {
      value,
      normalizedValue,
      hasValue: value.length > 0,
      present: normalizedValue.length > 0
    }
  }

  normalizeQueryValue(value) {
    return value
      .replace(/Ä/g, "Ae")
      .replace(/Ö/g, "Oe")
      .replace(/Ü/g, "Ue")
      .replace(/ä/g, "ae")
      .replace(/ö/g, "oe")
      .replace(/ü/g, "ue")
      .replace(/ß/g, "ss")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
      .replace(/\s+/g, " ")
  }
}

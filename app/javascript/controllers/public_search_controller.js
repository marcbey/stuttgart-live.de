import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "panel", "results", "idleTemplate"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 180 }
  }

  connect() {
    this.abortController = null
    this.lastRequestUrl = null
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
      const firstResult = this.resultLinks[0]
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
    const currentIndex = this.resultLinks.indexOf(event.currentTarget)
    if (currentIndex === -1) {
      return
    }

    if (event.key === "ArrowDown") {
      const nextResult = this.resultLinks[currentIndex + 1]
      if (!nextResult) {
        return
      }

      event.preventDefault()
      nextResult.focus()
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()

      const previousResult = this.resultLinks[currentIndex - 1]
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

  async fetchResults() {
    const requestUrl = this.buildRequestUrl()
    if (requestUrl === this.lastRequestUrl) {
      return
    }

    this.abortPendingRequest()
    this.abortController = new AbortController()

    try {
      const response = await fetch(requestUrl, {
        headers: { Accept: "text/html" },
        signal: this.abortController.signal
      })

      if (!response.ok) {
        throw new Error(`Search request failed with status ${response.status}`)
      }

      this.resultsTarget.innerHTML = await response.text()
      this.lastRequestUrl = requestUrl
    } catch (error) {
      if (error.name === "AbortError") {
        return
      }

      this.resultsTarget.innerHTML = `
        <div class="public-search-overlay-empty">
          <h2>Suche gerade nicht verfügbar</h2>
          <p>Bitte versuche es in einem Moment erneut.</p>
        </div>
      `
      this.lastRequestUrl = null
    } finally {
      this.abortController = null
    }
  }

  scheduleSearch() {
    this.clearScheduledSearch()
    this.searchTimeout = window.setTimeout(() => this.fetchResults(), this.debounceValue)
  }

  renderIdleState() {
    this.resultsTarget.innerHTML = this.idleTemplateTarget.innerHTML
    this.lastRequestUrl = null
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
    this.clearTarget.classList.toggle("public-search-clear-visible", this.query.present)
  }

  buildRequestUrl() {
    const url = new URL(this.searchUrlValue, window.location.origin)
    const params = new URLSearchParams(new FormData(this.element))

    params.set("q", this.query.value)
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

  get resultLinks() {
    return Array.from(this.resultsTarget.querySelectorAll("a.public-search-result"))
  }

  get query() {
    const value = this.inputTarget.value.toString().trim()

    return {
      value,
      present: value.length > 0
    }
  }
}

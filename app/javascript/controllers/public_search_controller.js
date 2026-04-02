import { Controller } from "@hotwired/stimulus"

const PLACEHOLDER_TYPING_DELAY = 70
const PLACEHOLDER_HOLD_DELAY = 3000
const PLACEHOLDER_BLINK_DELAY = 180
const PLACEHOLDER_BLINK_CYCLES = 3
const PLACEHOLDER_CLEAR_DELAY = 300
const PLACEHOLDER_VISIBLE_OPACITY = 1
const PLACEHOLDER_HIDDEN_OPACITY = 0

export default class extends Controller {
  static targets = ["input", "clear", "panel", "results", "idleTemplate"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 180 },
    placeholderPhrases: Array
  }

  connect() {
    this.abortController = null
    this.lastRequestKey = null
    this.searchTimeout = null
    this.placeholderTimeout = null
    this.placeholderAnimationActive = false
    this.currentPlaceholderIndex = 0
    this.activePlaceholderIndex = 0
    this.boundHandlePointerDown = this.handlePointerDown.bind(this)
    this.boundHandleDocumentKeydown = this.handleDocumentKeydown.bind(this)
    this.boundHandleReducedMotionChange = this.handleReducedMotionChange.bind(this)
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")

    document.addEventListener("pointerdown", this.boundHandlePointerDown)
    document.addEventListener("keydown", this.boundHandleDocumentKeydown)
    this.observeReducedMotionPreference()
    this.syncControls()
    this.syncPlaceholderAnimation()
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.boundHandlePointerDown)
    document.removeEventListener("keydown", this.boundHandleDocumentKeydown)
    this.unobserveReducedMotionPreference()
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.stopPlaceholderAnimation()
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
    this.syncPlaceholderAnimation()
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
    this.syncPlaceholderAnimation()
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

  syncPlaceholderAnimation() {
    if (this.query.hasValue) {
      this.stopPlaceholderAnimation({ advance: true })
      return
    }

    if (this.prefersReducedMotion || this.placeholderPhrases.length < 2) {
      this.stopPlaceholderAnimation()
      this.setPlaceholder(this.defaultPlaceholder)
      this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
      return
    }

    if (this.placeholderAnimationActive) {
      return
    }

    this.startPlaceholderAnimation()
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

  startPlaceholderAnimation() {
    if (!this.placeholderPhrases.length) {
      return
    }

    this.stopPlaceholderAnimation()
    this.placeholderAnimationActive = true
    this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
    this.runPlaceholderSequence()
  }

  stopPlaceholderAnimation({ advance = false } = {}) {
    if (advance && this.placeholderPhrases.length) {
      this.currentPlaceholderIndex = this.nextPlaceholderIndex(this.activePlaceholderIndex)
    }

    this.placeholderAnimationActive = false
    this.clearPlaceholderTimer()
    this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
  }

  runPlaceholderSequence() {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    const phrase = this.currentPlaceholderPhrase
    this.activePlaceholderIndex = this.currentPlaceholderIndex
    this.setPlaceholder("")
    this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
    this.typePlaceholderPhrase(phrase, 1)
  }

  typePlaceholderPhrase(phrase, length) {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    if (length > phrase.length) {
      this.schedulePlaceholderStep(() => this.fadePlaceholderOut(phrase, 0), PLACEHOLDER_HOLD_DELAY)
      return
    }

    this.setPlaceholder(phrase.slice(0, length))
    this.schedulePlaceholderStep(() => this.typePlaceholderPhrase(phrase, length + 1), PLACEHOLDER_TYPING_DELAY)
  }

  fadePlaceholderOut(phrase, cycle) {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    this.setPlaceholder(phrase)
    this.setPlaceholderOpacity(PLACEHOLDER_HIDDEN_OPACITY)

    if (cycle >= PLACEHOLDER_BLINK_CYCLES) {
      this.schedulePlaceholderStep(() => this.finishPlaceholderCycle(), PLACEHOLDER_BLINK_DELAY)
      return
    }

    this.schedulePlaceholderStep(() => this.fadePlaceholderIn(phrase, cycle), PLACEHOLDER_BLINK_DELAY)
  }

  fadePlaceholderIn(phrase, cycle) {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    this.setPlaceholder(phrase)
    this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
    this.schedulePlaceholderStep(() => this.fadePlaceholderOut(phrase, cycle + 1), PLACEHOLDER_BLINK_DELAY)
  }

  finishPlaceholderCycle() {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    this.setPlaceholder("")
    this.setPlaceholderOpacity(PLACEHOLDER_VISIBLE_OPACITY)
    if (this.placeholderPhrases.length) {
      this.currentPlaceholderIndex = this.nextPlaceholderIndex(this.activePlaceholderIndex)
    }

    this.schedulePlaceholderStep(() => this.runPlaceholderSequence(), PLACEHOLDER_CLEAR_DELAY)
  }

  schedulePlaceholderStep(callback, delay) {
    this.clearPlaceholderTimer()
    this.placeholderTimeout = window.setTimeout(() => {
      this.placeholderTimeout = null
      callback()
    }, delay)
  }

  clearPlaceholderTimer() {
    window.clearTimeout(this.placeholderTimeout)
    this.placeholderTimeout = null
  }

  handleReducedMotionChange() {
    this.syncPlaceholderAnimation()
  }

  observeReducedMotionPreference() {
    if (typeof this.reduceMotionQuery.addEventListener === "function") {
      this.reduceMotionQuery.addEventListener("change", this.boundHandleReducedMotionChange)
      return
    }

    this.reduceMotionQuery.addListener(this.boundHandleReducedMotionChange)
  }

  unobserveReducedMotionPreference() {
    if (typeof this.reduceMotionQuery.removeEventListener === "function") {
      this.reduceMotionQuery.removeEventListener("change", this.boundHandleReducedMotionChange)
      return
    }

    this.reduceMotionQuery.removeListener(this.boundHandleReducedMotionChange)
  }

  shouldAnimatePlaceholder() {
    return this.placeholderAnimationActive && !this.query.hasValue && !this.prefersReducedMotion && this.placeholderPhrases.length > 1
  }

  setPlaceholder(value) {
    this.inputTarget.setAttribute("placeholder", value)
  }

  setPlaceholderOpacity(value) {
    this.inputTarget.style.setProperty("--public-search-placeholder-opacity", value)
  }

  nextPlaceholderIndex(index) {
    return (index + 1) % this.placeholderPhrases.length
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

  get placeholderPhrases() {
    return (this.hasPlaceholderPhrasesValue ? this.placeholderPhrasesValue : [])
      .filter((phrase) => typeof phrase === "string" && phrase.length > 0)
  }

  get currentPlaceholderPhrase() {
    return this.placeholderPhrases[this.currentPlaceholderIndex] || this.defaultPlaceholder
  }

  get defaultPlaceholder() {
    return this.placeholderPhrases[0] || ""
  }

  get prefersReducedMotion() {
    return this.reduceMotionQuery.matches
  }
}

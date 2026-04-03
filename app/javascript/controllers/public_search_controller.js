import { Controller } from "@hotwired/stimulus"

const PLACEHOLDER_TYPING_BASE_DELAY = 92
const PLACEHOLDER_ENTRY_GAP_BASE_DELAY = 360
const PLACEHOLDER_CURSOR_BLINK_DELAY = 180
const PLACEHOLDER_TYPING_CADENCE = [-18, 14, -6, 20, -12, 10, 4, -4]

export default class extends Controller {
  static targets = ["input", "clear", "panel", "results", "idleTemplate", "placeholder", "placeholderText", "placeholderCursor"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 180 },
    placeholderSequence: Array
  }

  connect() {
    this.abortController = null
    this.lastRequestKey = null
    this.searchTimeout = null
    this.placeholderTimeout = null
    this.placeholderAnimationActive = false
    this.currentPlaceholderIndex = 0
    this.hasShownInitialPlaceholder = false
    this.boundHandlePointerDown = this.handlePointerDown.bind(this)
    this.boundHandleDocumentKeydown = this.handleDocumentKeydown.bind(this)
    this.boundHandleReducedMotionChange = this.handleReducedMotionChange.bind(this)
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")

    document.addEventListener("pointerdown", this.boundHandlePointerDown)
    document.addEventListener("keydown", this.boundHandleDocumentKeydown)
    this.observeReducedMotionPreference()
    this.inputTarget.setAttribute("placeholder", this.defaultPlaceholder)
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

  handleInputFocus() {
    if (!this.query.hasValue) {
      this.stopPlaceholderAnimation({ reset: true })
      this.renderPlaceholder("")
      this.setPlaceholderVisibility(false)
      this.inputTarget.value = ""
    }

    this.open()
  }

  handleInputBlur() {
    if (this.query.hasValue) {
      return
    }

    this.syncPlaceholderAnimation()
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
      this.stopPlaceholderAnimation({ reset: true })
      this.setPlaceholderVisibility(false)
      return
    }

    this.setPlaceholderVisibility(true)

    if (this.prefersReducedMotion || this.placeholderSequence.length <= 1) {
      this.stopPlaceholderAnimation()
      this.renderPlaceholder(this.defaultPlaceholder)
      this.setCursorVisibility(true)
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
    if (!this.placeholderSequence.length) {
      return
    }

    this.stopPlaceholderAnimation()
    this.placeholderAnimationActive = true
    this.runPlaceholderSequence()
  }

  stopPlaceholderAnimation({ reset = false } = {}) {
    if (reset) {
      this.currentPlaceholderIndex = 0
      this.hasShownInitialPlaceholder = false
    }

    this.placeholderAnimationActive = false
    this.clearPlaceholderTimer()
  }

  runPlaceholderSequence() {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    const entry = this.currentPlaceholderEntry

    if (entry.instant) {
      this.renderPlaceholder(entry.text)
      this.runCursorHold(entry, 0)
      return
    }

    this.renderPlaceholder("")
    this.setCursorVisibility(true)
    this.typePlaceholderEntry(entry, 1)
  }

  typePlaceholderEntry(entry, length) {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    if (length > entry.text.length) {
      this.runCursorHold(entry, 0)
      return
    }

    this.renderPlaceholder(entry.text.slice(0, length))
    this.schedulePlaceholderStep(
      () => this.typePlaceholderEntry(entry, length + 1),
      this.typingDelayFor(entry.text, length)
    )
  }

  runCursorHold(entry, blinkStep) {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    const totalBlinkSteps = this.cursorBlinkSteps(entry)

    if (blinkStep >= totalBlinkSteps) {
      this.setCursorVisibility(true)
      this.finishPlaceholderCycle()
      return
    }

    this.setCursorVisibility(blinkStep % 2 === 0)
    this.schedulePlaceholderStep(() => this.runCursorHold(entry, blinkStep + 1), PLACEHOLDER_CURSOR_BLINK_DELAY)
  }

  finishPlaceholderCycle() {
    if (!this.shouldAnimatePlaceholder()) {
      return
    }

    if (!this.hasShownInitialPlaceholder && this.initialPlaceholderEntry) {
      this.hasShownInitialPlaceholder = true
      this.currentPlaceholderIndex = 0
      this.schedulePlaceholderStep(() => this.runPlaceholderSequence(), this.entryGapDelayFor(this.currentPlaceholderIndex))
      return
    }

    this.currentPlaceholderIndex = this.nextPlaceholderIndex(this.currentPlaceholderIndex)
    this.schedulePlaceholderStep(() => this.runPlaceholderSequence(), this.entryGapDelayFor(this.currentPlaceholderIndex))
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
    return this.placeholderAnimationActive && !this.query.hasValue && !this.prefersReducedMotion && this.placeholderSequence.length > 1
  }

  renderPlaceholder(value) {
    this.placeholderTextTarget.textContent = value
  }

  setPlaceholderVisibility(visible) {
    this.placeholderTarget.classList.toggle("public-search-placeholder-hidden", !visible)
  }

  setCursorVisibility(visible) {
    this.placeholderCursorTarget.classList.toggle("public-search-placeholder-cursor-hidden", !visible)
  }

  cursorBlinkSteps(entry) {
    if (entry.holdMs > 0) {
      return Math.max(Math.round(entry.holdMs / PLACEHOLDER_CURSOR_BLINK_DELAY), 0)
    }

    const blinkCount = Number(entry.cursorBlinks || 0)
    return Math.max(blinkCount * 2, 0)
  }

  typingDelayFor(text, length) {
    const character = text[length - 1] || ""
    const cadence = PLACEHOLDER_TYPING_CADENCE[(length - 1) % PLACEHOLDER_TYPING_CADENCE.length]

    if (/[.,:;!?]/.test(character)) {
      return PLACEHOLDER_TYPING_BASE_DELAY + 150 + cadence
    }

    if (character === " ") {
      return PLACEHOLDER_TYPING_BASE_DELAY + 75 + cadence
    }

    if (length <= 3) {
      return PLACEHOLDER_TYPING_BASE_DELAY + 28 + cadence
    }

    return PLACEHOLDER_TYPING_BASE_DELAY + cadence
  }

  entryGapDelayFor(index) {
    const cadence = [40, 120, 0, 70, 25, 95][index % 6]
    return PLACEHOLDER_ENTRY_GAP_BASE_DELAY + cadence
  }

  nextPlaceholderIndex(index) {
    return (index + 1) % this.loopingPlaceholderSequence.length
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

  get placeholderSequence() {
    return (this.hasPlaceholderSequenceValue ? this.placeholderSequenceValue : [])
      .map((entry) => ({
        text: typeof entry?.text === "string" ? entry.text : "",
        cursorBlinks: Number(entry?.cursor_blinks ?? entry?.cursorBlinks ?? 0),
        holdMs: Number(entry?.hold_ms ?? entry?.holdMs ?? 0),
        instant: entry?.instant === true,
        repeat: entry?.repeat !== false
      }))
      .filter((entry) => entry.text.length > 0)
  }

  get currentPlaceholderEntry() {
    if (!this.hasShownInitialPlaceholder && this.initialPlaceholderEntry) {
      return this.initialPlaceholderEntry
    }

    return this.loopingPlaceholderSequence[this.currentPlaceholderIndex] || { text: this.defaultPlaceholder, cursorBlinks: 0, holdMs: 0, instant: false, repeat: true }
  }

  get defaultPlaceholder() {
    return this.placeholderSequence[0]?.text || ""
  }

  get initialPlaceholderEntry() {
    return this.placeholderSequence.find((entry) => entry.repeat === false) || null
  }

  get loopingPlaceholderSequence() {
    const loopEntries = this.placeholderSequence.filter((entry) => entry.repeat !== false)
    return loopEntries.length > 0 ? loopEntries : this.placeholderSequence
  }

  get prefersReducedMotion() {
    return this.reduceMotionQuery.matches
  }
}

import { Controller } from "@hotwired/stimulus"

const PLACEHOLDER_TYPING_BASE_DELAY = 40
const PLACEHOLDER_ENTRY_GAP_BASE_DELAY = 220
const PLACEHOLDER_CURSOR_BLINK_DELAY = 130
const PLACEHOLDER_SEQUENCE_START_DELAY = 2000
const PLACEHOLDER_TYPING_CADENCE = [-18, 14, -6, 20, -12, 10, 4, -4]
const CALENDAR_WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
const CALENDAR_MONTH_FORMATTER = new Intl.DateTimeFormat("de-DE", { month: "long", year: "numeric" })

export default class extends Controller {
  static targets = [
    "input",
    "clear",
    "panel",
    "results",
    "idleTemplate",
    "placeholder",
    "placeholderText",
    "placeholderCursor",
    "calendarButton",
    "calendarPanel",
    "calendarMonthLabel",
    "calendarGrid",
    "eventDateInput"
  ]
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
    this.placeholderStartTimeout = null
    this.placeholderAnimationActive = false
    this.currentPlaceholderIndex = 0
    this.hasShownInitialPlaceholder = false
    this.calendarDate = this.initialCalendarDate()
    this.selectedCalendarDate = this.selectedDateFromQuery()
    this.selectedCalendarRange = this.selectedRangeFromQuery()
    this.previewCalendarRangeSelection = null
    this.pendingRangeStart = this.selectedCalendarRange?.start || this.selectedCalendarDate
    this.boundHandlePointerDown = this.handlePointerDown.bind(this)
    this.boundHandleDocumentKeydown = this.handleDocumentKeydown.bind(this)
    this.boundHandleReducedMotionChange = this.handleReducedMotionChange.bind(this)
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")

    document.addEventListener("pointerdown", this.boundHandlePointerDown)
    document.addEventListener("keydown", this.boundHandleDocumentKeydown)
    this.observeReducedMotionPreference()
    this.inputTarget.setAttribute("placeholder", this.defaultPlaceholder)
    this.renderCalendar()
    this.syncControls()
    this.setPlaceholderVisibility(false)
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
    this.closeCalendar()
    this.inputTarget.focus()

    if (this.currentLocationHasQuery()) {
      this.element.requestSubmit()
    }
  }

  close() {
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.panelTarget.hidden = true
    this.closeCalendar()
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

    if (event.key === "Escape" && this.calendarOpen) {
      event.preventDefault()
      this.closeCalendar()
      this.calendarButtonTarget.focus()
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

  toggleCalendar(event) {
    event.preventDefault()

    if (this.calendarOpen) {
      this.closeCalendar()
      this.inputTarget.focus()
      return
    }

    this.openCalendar()
  }

  previousCalendarMonth(event) {
    event.preventDefault()

    this.calendarDate = new Date(this.calendarDate.getFullYear(), this.calendarDate.getMonth() - 1, 1)
    this.renderCalendar()
  }

  nextCalendarMonth(event) {
    event.preventDefault()

    this.calendarDate = new Date(this.calendarDate.getFullYear(), this.calendarDate.getMonth() + 1, 1)
    this.renderCalendar()
  }

  selectCalendarDate(event) {
    event.preventDefault()

    const selectedDate = this.dateFromKey(event.currentTarget.dataset.date)
    if (!selectedDate) {
      return
    }

    if (!this.pendingRangeStart || this.rangeComplete) {
      this.pendingRangeStart = selectedDate
      this.selectedCalendarDate = selectedDate
      this.selectedCalendarRange = null
      this.previewCalendarRangeSelection = null
      this.renderCalendar()
      return
    }

    const rangeStart = this.earlierDate(this.pendingRangeStart, selectedDate)
    const rangeEnd = this.laterDate(this.pendingRangeStart, selectedDate)
    this.selectedCalendarRange = { start: rangeStart, end: rangeEnd }
    this.selectedCalendarDate = null
    this.previewCalendarRangeSelection = null
    this.pendingRangeStart = rangeStart
    this.calendarDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
    this.inputTarget.value = this.formatCalendarRangeQuery(rangeStart, rangeEnd)
    this.clearEventDateInput()
    this.syncControls()
    this.syncPlaceholderAnimation()
    this.closeCalendar()
    this.closeSearchPanel()
    this.element.requestSubmit()
  }

  previewCalendarRange(event) {
    if (!this.pendingRangeStart || this.rangeComplete) {
      return
    }

    const previewDate = this.dateFromKey(event.currentTarget.dataset.date)
    if (!previewDate) {
      return
    }

    const nextPreviewRange = this.calendarRangeFor(this.pendingRangeStart, previewDate)
    if (this.sameCalendarRange(this.previewCalendarRangeSelection, nextPreviewRange)) {
      return
    }

    this.previewCalendarRangeSelection = nextPreviewRange
    this.renderCalendar()
  }

  clearCalendarRangePreview() {
    if (!this.previewCalendarRangeSelection || this.rangeComplete) {
      return
    }

    this.previewCalendarRangeSelection = null
    this.renderCalendar()
  }

  handleCalendarKeydown(event) {
    if (event.key !== "Escape") {
      return
    }

    event.preventDefault()
    this.closeCalendar()
    this.calendarButtonTarget.focus()
  }

  handleCalendarDayKeydown(event) {
    const currentDate = this.dateFromKey(event.currentTarget.dataset.date)
    if (!currentDate) {
      return
    }

    const offsetByKey = {
      ArrowLeft: -1,
      ArrowRight: 1,
      ArrowUp: -7,
      ArrowDown: 7,
      PageUp: -30,
      PageDown: 30
    }

    if (event.key === "Home") {
      event.preventDefault()
      this.focusCalendarDayByOffset(event.currentTarget, -this.calendarWeekdayIndex(currentDate))
      return
    }

    if (event.key === "End") {
      event.preventDefault()
      this.focusCalendarDayByOffset(event.currentTarget, 6 - this.calendarWeekdayIndex(currentDate))
      return
    }

    if (!Object.prototype.hasOwnProperty.call(offsetByKey, event.key)) {
      return
    }

    event.preventDefault()
    this.focusCalendarDayByOffset(event.currentTarget, offsetByKey[event.key])
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
    this.closeCalendar()
    this.panelTarget.hidden = false
  }

  closeSearchPanel() {
    this.abortPendingRequest()
    this.clearScheduledSearch()
    this.panelTarget.hidden = true
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

    if (this.prefersReducedMotion || this.placeholderSequence.length === 0) {
      this.schedulePlaceholderAnimationStart({ animate: false })
      return
    }

    if (this.placeholderAnimationActive) {
      return
    }

    this.schedulePlaceholderAnimationStart()
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

  schedulePlaceholderAnimationStart({ animate = true } = {}) {
    if (this.placeholderStartTimeout) {
      return
    }

    this.placeholderStartTimeout = window.setTimeout(() => {
      this.placeholderStartTimeout = null
      if (this.query.hasValue) {
        return
      }

      this.setPlaceholderVisibility(true)

      if (animate) {
        this.startPlaceholderAnimation()
      } else {
        this.stopPlaceholderAnimation()
        this.renderPlaceholder(this.defaultPlaceholder)
        this.setCursorVisibility(true)
      }
    }, PLACEHOLDER_SEQUENCE_START_DELAY)
  }

  stopPlaceholderAnimation({ reset = false } = {}) {
    if (reset) {
      this.currentPlaceholderIndex = 0
      this.hasShownInitialPlaceholder = false
    }

    this.placeholderAnimationActive = false
    this.clearPlaceholderStartTimer()
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

  clearPlaceholderStartTimer() {
    window.clearTimeout(this.placeholderStartTimeout)
    this.placeholderStartTimeout = null
  }

  openCalendar() {
    this.closeSearchPanel()
    this.pausePlaceholderForCalendar()
    this.selectedCalendarRange = this.selectedRangeFromQuery()
    this.selectedCalendarDate = this.selectedDateFromQuery()
    this.previewCalendarRangeSelection = null
    this.pendingRangeStart = this.selectedCalendarRange?.start || this.selectedCalendarDate
    this.calendarDate = this.selectedCalendarRange?.start || this.selectedCalendarDate || this.calendarDate || this.today
    this.renderCalendar()
    this.calendarPanelTarget.hidden = false
    this.calendarButtonTarget.setAttribute("aria-expanded", "true")

    const selectedDay = this.calendarGridTarget.querySelector(".public-search-calendar-day-selected")
    const today = this.calendarGridTarget.querySelector(".public-search-calendar-day-today")
    const firstCurrentMonthDay = this.calendarGridTarget.querySelector(".public-search-calendar-day:not(.public-search-calendar-day-muted)")
    const initialFocusTarget = selectedDay || today || firstCurrentMonthDay

    if (initialFocusTarget) {
      initialFocusTarget.focus()
    }
  }

  closeCalendar() {
    if (!this.hasCalendarPanelTarget) {
      return
    }

    const wasOpen = !this.calendarPanelTarget.hidden
    this.calendarPanelTarget.hidden = true
    this.calendarButtonTarget.setAttribute("aria-expanded", "false")

    if (wasOpen && !this.query.hasValue) {
      this.syncPlaceholderAnimation()
    }
  }

  renderCalendar() {
    if (!this.hasCalendarGridTarget) {
      return
    }

    const monthStart = new Date(this.calendarDate.getFullYear(), this.calendarDate.getMonth(), 1)
    const gridStart = this.calendarGridStart(monthStart)
    const todayKey = this.dateKey(this.today)
    const querySelectedDate = this.selectedDateFromQuery()
    const committedRange = this.selectedRangeFromQuery() || this.selectedCalendarRange
    const selectedRange = committedRange || this.previewCalendarRangeSelection
    const selectedDate = querySelectedDate || this.selectedCalendarDate || selectedRange?.start
    const selectedKey = selectedDate ? this.dateKey(selectedDate) : null
    const selectedRangeStartKey = selectedRange ? this.dateKey(selectedRange.start) : null
    const selectedRangeEndKey = selectedRange ? this.dateKey(selectedRange.end) : null
    const fragment = document.createDocumentFragment()

    this.calendarMonthLabelTarget.textContent = CALENDAR_MONTH_FORMATTER.format(monthStart)
    this.calendarGridTarget.innerHTML = ""

    for (let dayIndex = 0; dayIndex < 42; dayIndex += 1) {
      const date = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + dayIndex)
      const dateKey = this.dateKey(date)
      const dayButton = document.createElement("button")
      const pastDate = date < this.today

      dayButton.type = "button"
      dayButton.className = "public-search-calendar-day"
      dayButton.textContent = date.getDate().toString()
      dayButton.dataset.date = dateKey
      dayButton.dataset.action = pastDate ? "" : "click->public-search#selectCalendarDate keydown->public-search#handleCalendarDayKeydown mouseenter->public-search#previewCalendarRange focus->public-search#previewCalendarRange"
      dayButton.setAttribute("aria-label", `${CALENDAR_WEEKDAYS[this.calendarWeekdayIndex(date)]}, ${this.formatCalendarQuery(date)}`)

      if (date.getMonth() !== monthStart.getMonth()) {
        dayButton.classList.add("public-search-calendar-day-muted")
      }

      if (pastDate) {
        dayButton.disabled = true
        dayButton.classList.add("public-search-calendar-day-disabled")
      }

      if (dateKey === todayKey) {
        dayButton.classList.add("public-search-calendar-day-today")
      }

      if (selectedRange && this.dateInRange(date, selectedRange)) {
        dayButton.classList.add("public-search-calendar-day-in-range")
      }

      if (dateKey === selectedRangeStartKey || dateKey === selectedRangeEndKey) {
        dayButton.classList.add("public-search-calendar-day-range-edge")
      }

      if (dateKey === selectedKey) {
        dayButton.classList.add("public-search-calendar-day-selected")
        dayButton.setAttribute("aria-pressed", "true")
      } else {
        dayButton.setAttribute("aria-pressed", "false")
      }

      fragment.appendChild(dayButton)
    }

    this.calendarGridTarget.appendChild(fragment)
  }

  calendarGridStart(monthStart) {
    const mondayOffset = this.calendarWeekdayIndex(monthStart)
    return new Date(monthStart.getFullYear(), monthStart.getMonth(), monthStart.getDate() - mondayOffset)
  }

  calendarWeekdayIndex(date) {
    return (date.getDay() + 6) % 7
  }

  focusCalendarDayByOffset(currentTarget, offset) {
    const currentDate = this.dateFromKey(currentTarget.dataset.date)
    if (!currentDate) {
      return
    }

    const targetDate = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate() + offset)

    if (targetDate.getMonth() !== this.calendarDate.getMonth()) {
      this.calendarDate = new Date(targetDate.getFullYear(), targetDate.getMonth(), 1)
      this.renderCalendar()
    }

    this.calendarGridTarget.querySelector(`[data-date="${this.dateKey(targetDate)}"]`)?.focus()
  }

  pausePlaceholderForCalendar() {
    if (this.query.hasValue) {
      return
    }

    this.stopPlaceholderAnimation({ reset: true })
    this.renderPlaceholder(this.defaultPlaceholder)
    this.setPlaceholderVisibility(true)
    this.setCursorVisibility(false)
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
    return this.placeholderAnimationActive && !this.query.hasValue && !this.prefersReducedMotion && this.placeholderSequence.length > 0
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
    if (entry.cursorBlinks === null) {
      return Number.POSITIVE_INFINITY
    }

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

  selectedDateFromQuery() {
    const match = this.inputTarget.value.trim().match(/^am\s+(\d{1,2})\.(\d{1,2})\.(\d{4})$/i)
    if (!match) {
      return null
    }

    const date = new Date(Number(match[3]), Number(match[2]) - 1, Number(match[1]))
    if (date.getFullYear() !== Number(match[3]) || date.getMonth() !== Number(match[2]) - 1 || date.getDate() !== Number(match[1])) {
      return null
    }

    return date
  }

  selectedRangeFromQuery() {
    const match = this.inputTarget.value.trim().match(/^von\s+(\d{1,2})\.(\d{1,2})\.(\d{4})\s+bis\s+(\d{1,2})\.(\d{1,2})\.(\d{4})$/i)
    if (!match) {
      return null
    }

    const start = new Date(Number(match[3]), Number(match[2]) - 1, Number(match[1]))
    const end = new Date(Number(match[6]), Number(match[5]) - 1, Number(match[4]))
    if (!this.validDateParts(start, Number(match[3]), Number(match[2]), Number(match[1])) || !this.validDateParts(end, Number(match[6]), Number(match[5]), Number(match[4]))) {
      return null
    }

    return {
      start: this.earlierDate(start, end),
      end: this.laterDate(start, end)
    }
  }

  initialCalendarDate() {
    const selectedDate = this.selectedDateFromQuery()
    const date = selectedDate || this.today

    return new Date(date.getFullYear(), date.getMonth(), 1)
  }

  dateFromKey(value) {
    const match = value?.match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (!match) {
      return null
    }

    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    if (this.dateKey(date) !== value) {
      return null
    }

    return date
  }

  dateKey(date) {
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, "0")
    const day = date.getDate().toString().padStart(2, "0")

    return `${year}-${month}-${day}`
  }

  formatCalendarQuery(date) {
    return `am ${date.getDate()}.${date.getMonth() + 1}.${date.getFullYear()}`
  }

  formatCalendarRangeQuery(start, end) {
    if (this.dateKey(start) === this.dateKey(end)) {
      return this.formatCalendarQuery(start)
    }

    return `von ${start.getDate()}.${start.getMonth() + 1}.${start.getFullYear()} bis ${end.getDate()}.${end.getMonth() + 1}.${end.getFullYear()}`
  }

  validDateParts(date, year, month, day) {
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
  }

  dateInRange(date, range) {
    const key = this.dateKey(date)
    return key >= this.dateKey(range.start) && key <= this.dateKey(range.end)
  }

  calendarRangeFor(first, second) {
    return {
      start: this.earlierDate(first, second),
      end: this.laterDate(first, second)
    }
  }

  sameCalendarRange(first, second) {
    if (!first || !second) {
      return false
    }

    return this.dateKey(first.start) === this.dateKey(second.start) && this.dateKey(first.end) === this.dateKey(second.end)
  }

  earlierDate(first, second) {
    return this.dateKey(first) <= this.dateKey(second) ? first : second
  }

  laterDate(first, second) {
    return this.dateKey(first) >= this.dateKey(second) ? first : second
  }

  clearEventDateInput() {
    if (this.hasEventDateInputTarget) {
      this.eventDateInputTarget.value = ""
    }
  }

  get rangeComplete() {
    return this.selectedCalendarRange?.start && this.selectedCalendarRange?.end
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
        cursorBlinks: entry?.cursor_blinks === null || entry?.cursorBlinks === null ? null : Number(entry?.cursor_blinks ?? entry?.cursorBlinks ?? 0),
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

  get calendarOpen() {
    return this.hasCalendarPanelTarget && !this.calendarPanelTarget.hidden
  }

  get today() {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), now.getDate())
  }
}

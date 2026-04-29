import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "clear"]
  static values = { delay: { type: Number, default: 180 } }

  connect() {
    this.restoreFocusAfterStreamRender = this.restoreFocusAfterStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.restoreFocusAfterStreamRender)
    this.toggleClear()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.restoreFocusAfterStreamRender)
    this.clearPendingSubmit()
  }

  queueSubmit() {
    this.toggleClear()
    this.clearPendingSubmit()
    this.submitTimeout = window.setTimeout(() => this.submit(), this.delayValue)
  }

  submitNow(event) {
    event.preventDefault()
    this.clearPendingSubmit()
    this.submit()
  }

  clear(event) {
    event.preventDefault()
    this.queryTarget.value = ""
    this.queryTarget.focus({ preventScroll: true })
    this.toggleClear()
    this.clearPendingSubmit()
    this.submit()
  }

  submit() {
    this.element.requestSubmit()
  }

  toggleClear() {
    if (!this.hasClearTarget) return

    this.clearTarget.classList.toggle("filter-date-clear-visible", this.queryTarget.value.length > 0)
  }

  clearPendingSubmit() {
    if (!this.submitTimeout) return

    window.clearTimeout(this.submitTimeout)
    this.submitTimeout = null
  }

  restoreFocusAfterStreamRender(event) {
    if (!this.queryTargetFocused()) return

    const selection = this.querySelection()
    const render = event.detail.render

    event.detail.render = (streamElement) => {
      render(streamElement)
      this.restoreQueryFocus(selection)
    }
  }

  queryTargetFocused() {
    return this.hasQueryTarget && document.activeElement === this.queryTarget
  }

  querySelection() {
    return {
      start: this.queryTarget.selectionStart,
      end: this.queryTarget.selectionEnd,
      direction: this.queryTarget.selectionDirection
    }
  }

  restoreQueryFocus(selection) {
    window.requestAnimationFrame(() => {
      if (!this.hasQueryTarget) return

      this.queryTarget.focus({ preventScroll: true })

      if (selection.start === null || selection.end === null) return

      this.queryTarget.setSelectionRange(selection.start, selection.end, selection.direction)
    })
  }
}

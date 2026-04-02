import { Controller } from "@hotwired/stimulus"
import { addSavedEvent, isSavedEvent, removeSavedEvent } from "../lib/saved_events_storage"

export default class extends Controller {
  static targets = [ "label" ]
  static values = {
    eventName: String,
    savedLabel: String,
    slug: String,
    unsavedLabel: String
  }

  connect() {
    this.handleSavedEventsChanged = this.handleSavedEventsChanged.bind(this)
    this.handleStorage = this.handleStorage.bind(this)
    this.clearHoverSuppression = this.clearHoverSuppression.bind(this)

    window.addEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.addEventListener("storage", this.handleStorage)
    this.render()
  }

  disconnect() {
    window.removeEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.removeEventListener("storage", this.handleStorage)
    this.cardElement?.removeEventListener("mouseleave", this.clearHoverSuppression)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasSlugValue) return

    const saved = isSavedEvent(this.slugValue)
    const changed = saved ? removeSavedEvent(this.slugValue) : addSavedEvent(this.slugValue)
    if (!changed) return

    if (saved) {
      this.suppressHoverUntilPointerLeaves()
    } else {
      this.clearHoverSuppression()
    }

    window.dispatchEvent(new CustomEvent("saved-events:changed", {
      detail: {
        saved: !saved,
        slug: this.slugValue
      }
    }))

    this.render()
  }

  handleSavedEventsChanged(event) {
    const changedSlug = event.detail?.slug?.toString()
    if (changedSlug && changedSlug !== this.slugValue) return

    this.render()
  }

  handleStorage() {
    this.render()
  }

  render() {
    if (!this.hasSlugValue) return

    const saved = isSavedEvent(this.slugValue)
    const label = this.buttonLabel(saved)

    if (saved) this.clearHoverSuppression()

    this.element.classList.toggle("is-saved", saved)
    this.element.setAttribute("aria-pressed", saved ? "true" : "false")
    this.element.setAttribute("aria-label", label)
    this.element.setAttribute("title", label)

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = label
    }
  }

  buttonLabel(saved) {
    const eventName = this.hasEventNameValue ? this.eventNameValue : "Event"
    const action = saved ? this.savedLabelValue : this.unsavedLabelValue
    return `${eventName} ${action}`.trim()
  }

  suppressHoverUntilPointerLeaves() {
    if (!this.cardElement) return

    this.element.blur()
    this.cardElement.classList.add("saved-event-hover-suppressed")
    this.cardElement.removeEventListener("mouseleave", this.clearHoverSuppression)
    this.cardElement.addEventListener("mouseleave", this.clearHoverSuppression, { once: true })
  }

  clearHoverSuppression() {
    this.cardElement?.classList.remove("saved-event-hover-suppressed")
  }

  get cardElement() {
    return this.element.closest(".event-card, .genre-lane-card, .home-slider-card")
  }
}

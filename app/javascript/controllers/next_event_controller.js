import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "preference", "headerActions"]
  static values = { enabled: { type: Boolean, default: true }, preferenceUrl: String }

  connect() {
    this.applyToggleState()
    this.syncActiveFromEditor()
  }

  toggleChanged() {
    if (!this.hasToggleTarget) return

    this.enabledValue = this.toggleTarget.checked
    this.syncPreferenceField()
    this.persistPreference()
  }

  applyToggleState() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = this.enabledValue
    }

    this.syncPreferenceField()
  }

  nextEventEnabled() {
    if (this.hasToggleTarget) return this.toggleTarget.checked

    return this.enabledValue
  }

  syncPreferenceField() {
    if (!this.hasPreferenceTarget) return

    this.preferenceTarget.value = this.nextEventEnabled() ? "1" : "0"
  }

  persistPreference() {
    if (!this.hasPreferenceUrlValue) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (!token) return

    const body = new URLSearchParams({ enabled: this.nextEventEnabled() ? "1" : "0" })
    fetch(this.preferenceUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"
      },
      credentials: "same-origin",
      body
    })
  }

  eventLinkClicked(event) {
    const eventId = Number.parseInt(event.currentTarget?.dataset?.nextEventEventId, 10)
    if (Number.isNaN(eventId)) return

    this.highlightEventById(eventId)
  }

  syncActiveFromEditor(event) {
    const frame = event?.target
    if (frame && frame.id !== "event_editor") return

    this.syncHeaderActions()

    const form = document.querySelector("turbo-frame#event_editor form.editor-form")
    if (!(form instanceof HTMLFormElement)) {
      this.highlightEventById(null)
      return
    }

    const eventId = this.eventIdFromEditorForm(form)
    if (eventId === null) {
      this.highlightEventById(null)
      return
    }

    this.highlightEventById(eventId)
  }

  syncActiveAfterSubmit(event) {
    if (!event?.detail?.success) return

    const target = event.target
    if (!(target instanceof HTMLFormElement)) return
    if (!target.id.startsWith("editor_form_")) return

    window.requestAnimationFrame(() => this.syncActiveFromEditor())
  }

  syncHeaderActions() {
    if (!this.hasHeaderActionsTarget) return

    const template = document.querySelector("turbo-frame#event_editor .editor-actions-template")
    this.headerActionsTarget.replaceChildren()
    if (!(template instanceof HTMLTemplateElement)) return

    this.headerActionsTarget.append(template.content.cloneNode(true))
  }

  highlightEventById(eventId) {
    const items = Array.from(document.querySelectorAll(".event-list-item"))
    items.forEach((item) => item.classList.remove("event-list-item-active"))

    if (eventId === null || eventId === undefined) return

    const activeLink = document.querySelector(`.event-link[data-next-event-event-id='${eventId}']`)
    const activeItem = activeLink?.closest(".event-list-item")
    if (activeItem) activeItem.classList.add("event-list-item-active")
  }

  eventIdFromEditorForm(form) {
    const match = form.id.match(/editor_form_event_(\d+)$/)
    if (!match) return null

    return Number.parseInt(match[1], 10)
  }
}

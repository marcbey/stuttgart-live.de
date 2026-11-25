import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { savedEventSlugs, writeSavedEvents } from "../lib/saved_events_storage"

export default class extends Controller {
  static values = { pageUrl: String }

  connect() {
    this.render = this.render.bind(this)
    window.addEventListener("saved-events:changed", this.render)
    window.addEventListener("storage", this.render)
    this.render()
  }

  disconnect() {
    window.removeEventListener("saved-events:changed", this.render)
    window.removeEventListener("storage", this.render)
  }

  clear(event) {
    event.preventDefault()
    event.stopPropagation()

    const sharedUrl = this.sharedSelectionUrl()
    const message = sharedUrl
      ? "Die geteilte Auswahl schließen und die Merkliste dieses Browsers leeren?"
      : "Die Merkliste dieses Browsers wirklich leeren?"
    if (!window.confirm(message)) return

    try {
      writeSavedEvents([])
    } catch (_error) {
      window.alert("Die Merkliste konnte nicht geleert werden. Bitte versuche es erneut.")
      return
    }

    if (sharedUrl) {
      sharedUrl.searchParams.delete("slugs[]")
      Turbo.visit(sharedUrl.toString(), { action: "replace" })
    }

    window.dispatchEvent(new CustomEvent("saved-events:changed", { detail: { cleared: true } }))
  }

  render() {
    this.element.hidden = savedEventSlugs().length === 0 && !this.sharedSelectionUrl()
  }

  sharedSelectionUrl() {
    const url = new URL(window.location.href)
    const pageUrl = new URL(this.pageUrlValue, window.location.origin)
    return url.pathname === pageUrl.pathname && url.searchParams.has("slugs[]") ? url : null
  }
}

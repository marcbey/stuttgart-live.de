import { Controller } from "@hotwired/stimulus"

const CONSENT_EVENT = "stuttgart-live:consent-changed"

export default class extends Controller {
  static targets = ["frame", "placeholder", "template"]

  connect() {
    this.sync = this.sync.bind(this)
    window.addEventListener(CONSENT_EVENT, this.sync)
    this.sync()
  }

  disconnect() {
    window.removeEventListener(CONSENT_EVENT, this.sync)
  }

  sync(event) {
    const preferences = event?.detail?.preferences || window.StuttgartLiveConsent?.preferences || {}

    if (preferences.media) {
      this.renderFrame()
    } else {
      this.renderPlaceholder()
    }
  }

  renderFrame() {
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.hidden = true
    }

    if (!this.frameTarget.hasChildNodes()) {
      this.frameTarget.appendChild(this.templateTarget.content.cloneNode(true))
    }
  }

  renderPlaceholder() {
    this.frameTarget.replaceChildren()

    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.hidden = false
    }
  }
}

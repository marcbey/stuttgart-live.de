import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mirror", "source"]

  connect() {
    this.sourceTargets.forEach((source) => this.syncSource(source))
  }

  sync(event) {
    this.syncSource(event.currentTarget)
  }

  syncSource(source) {
    const key = source.dataset.eventEditorSettingsKey
    if (!key) return

    const mirror = this.mirrorTargets.find((candidate) => candidate.dataset.eventEditorSettingsKey === key)
    if (!mirror) return

    mirror.value = source.type === "checkbox" ? (source.checked ? "1" : "0") : source.value
  }
}

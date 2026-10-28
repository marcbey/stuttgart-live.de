import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.scheduleUpdate()
  }

  labelTargetConnected() {
    this.scheduleUpdate()
  }

  labelTargetDisconnected() {
    this.scheduleUpdate()
  }

  scheduleUpdate() {
    if (this.updatePending) return

    this.updatePending = true
    queueMicrotask(() => {
      this.updatePending = false
      if (!this.element.isConnected) return

      const genres = new Set(this.labelTargets.map(label => label.dataset.genreName).filter(Boolean))
      this.element.dataset.genresMixed = String(genres.size > 1)
    })
  }
}

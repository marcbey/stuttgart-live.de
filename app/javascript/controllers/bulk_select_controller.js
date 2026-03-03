import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "toggleButton"]

  connect() {
    this.syncToggleLabel()
  }

  toggleAll() {
    const shouldSelect = !this.allSelected()

    this.itemTargets.forEach((checkbox) => {
      checkbox.checked = shouldSelect
    })

    this.syncToggleLabel()
  }

  syncToggleLabel() {
    if (!this.hasToggleButtonTarget) return

    this.toggleButtonTarget.textContent = this.allSelected() ? "Alle abwählen" : "Alle markieren"
  }

  allSelected() {
    return this.itemTargets.length > 0 && this.itemTargets.every((checkbox) => checkbox.checked)
  }
}

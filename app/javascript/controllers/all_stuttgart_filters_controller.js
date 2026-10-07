import { Controller } from "@hotwired/stimulus"

const OVERLAY_OPENED_EVENT = "design-preview:overlay-opened"
const OVERLAY_SOURCE = "all-stuttgart-filters"

export default class extends Controller {
  static targets = [ "dropdown" ]

  sync(event) {
    const openedDropdown = event.currentTarget
    if (!openedDropdown.open) return

    this.dropdownTargets.forEach((dropdown) => {
      if (dropdown !== openedDropdown) dropdown.open = false
    })
    window.dispatchEvent(new CustomEvent(OVERLAY_OPENED_EVENT, { detail: { source: OVERLAY_SOURCE } }))
  }

  closeAll() {
    this.dropdownTargets.forEach((dropdown) => {
      dropdown.open = false
    })
  }
}

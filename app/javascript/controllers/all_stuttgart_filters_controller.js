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

  filter(event) {
    const dropdown = event.currentTarget.closest("details")
    const query = this.normalize(event.currentTarget.value.trim())
    let matches = 0

    dropdown.querySelectorAll("[data-filter-option]").forEach((option) => {
      option.hidden = !this.normalize(option.textContent).includes(query)
      if (!option.hidden) matches += 1
    })

    dropdown.querySelector("[data-filter-empty]").hidden = matches > 0
  }

  normalize(value) {
    return value.toLocaleLowerCase("de").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/ß/g, "ss")
  }
}

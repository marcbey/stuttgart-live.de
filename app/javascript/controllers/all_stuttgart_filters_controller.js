import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dropdown" ]

  sync(event) {
    const openedDropdown = event.currentTarget
    if (!openedDropdown.open) return

    this.dropdownTargets.forEach((dropdown) => {
      if (dropdown !== openedDropdown) dropdown.open = false
    })
  }
}

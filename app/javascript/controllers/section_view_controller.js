import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "slider", "list", "button" ]

  connect() {
    this.showSlider()
  }

  toggle(event) {
    event.preventDefault()

    if (this.listTarget.hidden) {
      this.showList()
    } else {
      this.showSlider()
    }
  }

  showSlider() {
    if (this.hasSliderTarget) this.sliderTarget.hidden = false
    if (this.hasListTarget) this.listTarget.hidden = true
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-pressed", "false")
      this.buttonTarget.setAttribute("title", "Listenansicht")
    }
  }

  showList() {
    if (this.hasSliderTarget) this.sliderTarget.hidden = true
    if (this.hasListTarget) this.listTarget.hidden = false
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-pressed", "true")
      this.buttonTarget.setAttribute("title", "Kachelansicht")
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open() {
    this.element.dataset.interestsOpen = "true"
  }

  close() {
    this.element.dataset.interestsOpen = "false"
  }
}

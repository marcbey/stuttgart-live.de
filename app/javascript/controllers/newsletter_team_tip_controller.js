import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["profile", "title"]

  updateTitle() {
    this.titleTarget.value = this.profileTarget.selectedOptions[0]?.dataset.tipTitle || ""
  }
}

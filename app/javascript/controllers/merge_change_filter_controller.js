import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "scope", "changeType" ]

  connect() {
    this.sync()
  }

  sync() {
    const isLastMerge = this.scopeTarget.value === "last_merge"

    this.changeTypeTarget.disabled = !isLastMerge
    if (!isLastMerge) {
      this.changeTypeTarget.value = "all"
    }
  }

  submit() {
    this.sync()
    this.element.requestSubmit()
  }

  submitOnEnter(event) {
    event.preventDefault()
    this.submit()
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "mergeRun", "changeType" ]

  connect() {
    this.sync()
  }

  sync() {
    const mergeRunSelected = this.mergeRunTarget.value !== "all"

    this.changeTypeTarget.disabled = !mergeRunSelected
    if (!mergeRunSelected) {
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

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["persist"]
  static values = { key: String }

  connect() {
    if (!this.hasKeyValue) return

    this.restore()
    this.boundSave = this.save.bind(this)
    this.element.addEventListener("input", this.boundSave)
    this.element.addEventListener("change", this.boundSave)
  }

  disconnect() {
    if (!this.boundSave) return

    this.element.removeEventListener("input", this.boundSave)
    this.element.removeEventListener("change", this.boundSave)
  }

  restore() {
    const raw = window.localStorage.getItem(this.keyValue)
    if (!raw) return

    try {
      const values = JSON.parse(raw)
      this.persistTargets.forEach((input) => {
        if (input.value && input.value.length > 0) return

        const saved = values[input.name]
        if (typeof saved === "string") input.value = saved
      })
    } catch (_error) {
      window.localStorage.removeItem(this.keyValue)
    }
  }

  save() {
    if (!this.hasKeyValue) return

    const payload = {}
    this.persistTargets.forEach((input) => {
      payload[input.name] = input.value
    })

    window.localStorage.setItem(this.keyValue, JSON.stringify(payload))
  }

  clear(event) {
    event.preventDefault()

    this.persistTargets.forEach((input) => {
      input.value = ""
    })

    if (this.hasKeyValue) {
      window.localStorage.removeItem(this.keyValue)
    }

    this.element.requestSubmit()
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "button", "checkbox"]

  connect() {
    this.update = this.update.bind(this)

    this.update()
    window.requestAnimationFrame(this.update)
    window.addEventListener("resize", this.update)
    document.fonts?.ready.then(this.update)
  }

  disconnect() {
    window.removeEventListener("resize", this.update)
  }

  update() {
    if (!this.hasBodyTarget || !this.hasButtonTarget) return

    const wasChecked = this.hasCheckboxTarget ? this.checkboxTarget.checked : false

    this.element.classList.add("design-detail-preview-description-toggle--needs-more")
    if (this.hasCheckboxTarget) this.checkboxTarget.checked = false

    const needsToggle = this.bodyTarget.scrollHeight > this.bodyTarget.clientHeight + 2

    this.element.classList.toggle("design-detail-preview-description-toggle--needs-more", needsToggle)
    this.buttonTarget.hidden = !needsToggle

    if (this.hasCheckboxTarget) {
      this.checkboxTarget.checked = needsToggle && wasChecked
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "previewImage", "focusX", "focusY", "zoom", "focusXOutput", "focusYOutput", "zoomOutput" ]

  connect() {
    this.update()
  }

  update() {
    const focusX = this.readValue("focusX", 50)
    const focusY = this.readValue("focusY", 50)
    const zoom = this.readValue("zoom", 100)

    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.style.objectPosition = `${focusX}% ${focusY}%`
      this.previewImageTarget.style.transformOrigin = `${focusX}% ${focusY}%`
      this.previewImageTarget.style.transform = `scale(${(zoom / 100).toFixed(2)})`
    }

    if (this.hasFocusXOutputTarget) this.focusXOutputTarget.textContent = `${Math.round(focusX)}%`
    if (this.hasFocusYOutputTarget) this.focusYOutputTarget.textContent = `${Math.round(focusY)}%`
    if (this.hasZoomOutputTarget) this.zoomOutputTarget.textContent = `${Math.round(zoom)}%`
  }

  readValue(targetName, fallback) {
    const target = this[`${targetName}Target`]
    const value = Number.parseFloat(target?.value || "")
    return Number.isFinite(value) ? value : fallback
  }
}

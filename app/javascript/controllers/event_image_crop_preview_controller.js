import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "previewFrame",
    "previewImage",
    "focusX",
    "focusY",
    "zoom",
    "gridVariant",
    "focusXOutput",
    "focusYOutput",
    "zoomOutput",
    "saveGridVariant",
    "saveFocusX",
    "saveFocusY",
    "saveZoom"
  ]

  connect() {
    this.update()
  }

  update() {
    const focusX = this.readValue("focusX", 50)
    const focusY = this.readValue("focusY", 50)
    const zoom = this.readValue("zoom", 100)
    const gridVariant = this.hasGridVariantTarget ? this.gridVariantTarget.value : "1x1"

    this.updateFrameVariant(gridVariant)

    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.style.objectPosition = `${focusX}% ${focusY}%`
      this.previewImageTarget.style.transformOrigin = `${focusX}% ${focusY}%`
      this.previewImageTarget.style.transform = `scale(${(zoom / 100).toFixed(2)})`
    }

    if (this.hasFocusXOutputTarget) this.focusXOutputTarget.textContent = `${Math.round(focusX)}%`
    if (this.hasFocusYOutputTarget) this.focusYOutputTarget.textContent = `${Math.round(focusY)}%`
    if (this.hasZoomOutputTarget) this.zoomOutputTarget.textContent = `${Math.round(zoom)}%`

    if (this.hasSaveGridVariantTarget) this.saveGridVariantTarget.value = gridVariant
    if (this.hasSaveFocusXTarget) this.saveFocusXTarget.value = focusX
    if (this.hasSaveFocusYTarget) this.saveFocusYTarget.value = focusY
    if (this.hasSaveZoomTarget) this.saveZoomTarget.value = zoom
  }

  readValue(targetName, fallback) {
    const target = this[`${targetName}Target`]
    const value = Number.parseFloat(target?.value || "")
    return Number.isFinite(value) ? value : fallback
  }

  updateFrameVariant(gridVariant) {
    if (!this.hasPreviewFrameTarget) return

    this.previewFrameTarget.dataset.gridVariant = gridVariant
  }
}

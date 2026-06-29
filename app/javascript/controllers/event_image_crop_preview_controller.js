import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "previewFrame",
    "previewImage",
    "previewBox",
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
    this.boundUpdate = () => this.update()
    this.boundDrag = (event) => this.drag(event)
    this.boundEndDrag = () => this.endDrag()

    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.addEventListener("load", this.boundUpdate)
    }

    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(this.boundUpdate)
      if (this.hasPreviewFrameTarget) this.resizeObserver.observe(this.previewFrameTarget)
      if (this.hasPreviewImageTarget) this.resizeObserver.observe(this.previewImageTarget)
    }

    this.update()
  }

  disconnect() {
    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.removeEventListener("load", this.boundUpdate)
    }

    this.endDrag()
    this.resizeObserver?.disconnect()
  }

  update() {
    const focusX = this.readValue("focusX", 50)
    const focusY = this.readValue("focusY", 50)
    const zoom = this.readValue("zoom", 100)
    const gridVariant = this.hasGridVariantTarget ? this.gridVariantTarget.value : "1x1"

    this.updateFrameVariant(gridVariant)
    this.updatePreviewImage({ focusX, focusY, zoom })

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

  updatePreviewImage({ focusX, focusY, zoom }) {
    if (!this.hasPreviewFrameTarget || !this.hasPreviewImageTarget || !this.hasPreviewBoxTarget) return

    const cropMetrics = this.cropMetrics({ focusX, focusY, zoom })
    if (!cropMetrics) {
      this.previewBoxTarget.classList.add("is-hidden")
      return
    }

    this.previewImageTarget.style.left = `${cropMetrics.offsetX * 100}%`
    this.previewImageTarget.style.top = `${cropMetrics.offsetY * 100}%`
    this.previewImageTarget.style.width = `${cropMetrics.widthFactor * 100}%`
    this.previewImageTarget.style.height = `${cropMetrics.heightFactor * 100}%`

    this.previewBoxTarget.style.left = "0"
    this.previewBoxTarget.style.top = "0"
    this.previewBoxTarget.style.width = "100%"
    this.previewBoxTarget.style.height = "100%"
    this.previewBoxTarget.classList.remove("is-hidden")
  }

  startDrag(event) {
    if (!this.hasFocusXTarget || !this.hasFocusYTarget) return
    if (!this.hasPreviewFrameTarget || !this.hasPreviewImageTarget || !this.hasPreviewBoxTarget) return
    if (event.button !== undefined && event.button !== 0) return

    const focusX = this.readValue("focusX", 50)
    const focusY = this.readValue("focusY", 50)
    const zoom = this.readValue("zoom", 100)
    const cropMetrics = this.cropMetrics({ focusX, focusY, zoom })
    if (!cropMetrics || this.previewBoxTarget.classList.contains("is-hidden")) return

    this.dragState = {
      startClientX: event.clientX,
      startClientY: event.clientY,
      frameWidth: cropMetrics.frameWidth,
      frameHeight: cropMetrics.frameHeight,
      widthFactor: cropMetrics.widthFactor,
      heightFactor: cropMetrics.heightFactor,
      offsetX: cropMetrics.offsetX,
      offsetY: cropMetrics.offsetY
    }

    this.previewFrameTarget.classList.add("is-dragging")
    window.addEventListener("pointermove", this.boundDrag)
    window.addEventListener("pointerup", this.boundEndDrag)
    window.addEventListener("pointercancel", this.boundEndDrag)
    event.preventDefault()
  }

  drag(event) {
    if (!this.dragState) return

    const deltaX = event.clientX - this.dragState.startClientX
    const deltaY = event.clientY - this.dragState.startClientY
    const offsetX = this.clampCropOffset(
      this.dragState.offsetX + (deltaX / this.dragState.frameWidth),
      this.dragState.widthFactor
    )
    const offsetY = this.clampCropOffset(
      this.dragState.offsetY + (deltaY / this.dragState.frameHeight),
      this.dragState.heightFactor
    )

    const focusX = ((0.5 - offsetX) / this.dragState.widthFactor) * 100
    const focusY = ((0.5 - offsetY) / this.dragState.heightFactor) * 100

    this.focusXTarget.value = focusX
    this.focusYTarget.value = focusY
    this.update()
  }

  endDrag() {
    this.dragState = null
    this.previewFrameTarget?.classList.remove("is-dragging")
    window.removeEventListener("pointermove", this.boundDrag)
    window.removeEventListener("pointerup", this.boundEndDrag)
    window.removeEventListener("pointercancel", this.boundEndDrag)
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  cropMetrics({ focusX, focusY, zoom }) {
    const naturalWidth = this.previewImageTarget.naturalWidth
    const naturalHeight = this.previewImageTarget.naturalHeight

    if (!naturalWidth || !naturalHeight) return null

    const frameRect = this.previewFrameTarget.getBoundingClientRect()
    if (!frameRect.width || !frameRect.height) return null

    const zoomScale = Math.max(zoom, 100) / 100
    const imageRatio = naturalWidth / naturalHeight
    const frameRatio = frameRect.width / frameRect.height
    const focusXRatio = focusX / 100
    const focusYRatio = focusY / 100

    const [widthFactor, heightFactor] = imageRatio > frameRatio
      ? [ (imageRatio / frameRatio) * zoomScale, zoomScale ]
      : [ zoomScale, (frameRatio / imageRatio) * zoomScale ]

    return {
      frameWidth: frameRect.width,
      frameHeight: frameRect.height,
      widthFactor,
      heightFactor,
      offsetX: this.clampCropOffset(0.5 - (focusXRatio * widthFactor), widthFactor),
      offsetY: this.clampCropOffset(0.5 - (focusYRatio * heightFactor), heightFactor)
    }
  }

  clampCropOffset(offset, sizeFactor) {
    return Math.max(Math.min(offset, 0), 1 - sizeFactor)
  }
}

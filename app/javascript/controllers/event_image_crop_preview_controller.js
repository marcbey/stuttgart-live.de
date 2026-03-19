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
    this.updateCropBox({ focusX, focusY, zoom })

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

  updateCropBox({ focusX, focusY, zoom }) {
    if (!this.hasPreviewFrameTarget || !this.hasPreviewImageTarget || !this.hasPreviewBoxTarget) return

    const naturalWidth = this.previewImageTarget.naturalWidth
    const naturalHeight = this.previewImageTarget.naturalHeight

    if (!naturalWidth || !naturalHeight) {
      this.previewBoxTarget.classList.add("is-hidden")
      return
    }

    const frameRect = this.previewFrameTarget.getBoundingClientRect()
    const imageRect = this.previewImageTarget.getBoundingClientRect()

    if (!frameRect.width || !frameRect.height || !imageRect.width || !imageRect.height) {
      this.previewBoxTarget.classList.add("is-hidden")
      return
    }

    const zoomScale = Math.max(zoom, 100) / 100
    const naturalRatio = naturalWidth / naturalHeight
    const frameRatio = frameRect.width / frameRect.height
    const coverScale = naturalRatio > frameRatio ? frameRect.height / naturalHeight : frameRect.width / naturalWidth

    const visibleNaturalWidth = Math.min(naturalWidth, frameRect.width / (coverScale * zoomScale))
    const visibleNaturalHeight = Math.min(naturalHeight, frameRect.height / (coverScale * zoomScale))
    const focusNaturalX = (focusX / 100) * naturalWidth
    const focusNaturalY = (focusY / 100) * naturalHeight
    const cropNaturalLeft = this.clamp(focusNaturalX - (visibleNaturalWidth / 2), 0, naturalWidth - visibleNaturalWidth)
    const cropNaturalTop = this.clamp(focusNaturalY - (visibleNaturalHeight / 2), 0, naturalHeight - visibleNaturalHeight)

    const left = (imageRect.left - frameRect.left) + ((cropNaturalLeft / naturalWidth) * imageRect.width)
    const top = (imageRect.top - frameRect.top) + ((cropNaturalTop / naturalHeight) * imageRect.height)
    const width = (visibleNaturalWidth / naturalWidth) * imageRect.width
    const height = (visibleNaturalHeight / naturalHeight) * imageRect.height

    this.previewBoxTarget.style.left = `${left}px`
    this.previewBoxTarget.style.top = `${top}px`
    this.previewBoxTarget.style.width = `${width}px`
    this.previewBoxTarget.style.height = `${height}px`
    this.previewBoxTarget.classList.remove("is-hidden")
  }

  startDrag(event) {
    if (!this.hasFocusXTarget || !this.hasFocusYTarget) return
    if (!this.hasPreviewFrameTarget || !this.hasPreviewImageTarget || !this.hasPreviewBoxTarget) return
    if (event.button !== undefined && event.button !== 0) return

    const naturalWidth = this.previewImageTarget.naturalWidth
    const naturalHeight = this.previewImageTarget.naturalHeight
    if (!naturalWidth || !naturalHeight || this.previewBoxTarget.classList.contains("is-hidden")) return

    const frameRect = this.previewFrameTarget.getBoundingClientRect()
    const imageRect = this.previewImageTarget.getBoundingClientRect()
    if (!frameRect.width || !frameRect.height || !imageRect.width || !imageRect.height) return

    const focusX = this.readValue("focusX", 50)
    const focusY = this.readValue("focusY", 50)
    const zoomScale = Math.max(this.readValue("zoom", 100), 100) / 100
    const naturalRatio = naturalWidth / naturalHeight
    const frameRatio = frameRect.width / frameRect.height
    const coverScale = naturalRatio > frameRatio ? frameRect.height / naturalHeight : frameRect.width / naturalWidth
    const visibleNaturalWidth = Math.min(naturalWidth, frameRect.width / (coverScale * zoomScale))
    const visibleNaturalHeight = Math.min(naturalHeight, frameRect.height / (coverScale * zoomScale))
    const focusNaturalX = (focusX / 100) * naturalWidth
    const focusNaturalY = (focusY / 100) * naturalHeight
    const cropNaturalLeft = this.clamp(focusNaturalX - (visibleNaturalWidth / 2), 0, naturalWidth - visibleNaturalWidth)
    const cropNaturalTop = this.clamp(focusNaturalY - (visibleNaturalHeight / 2), 0, naturalHeight - visibleNaturalHeight)

    this.dragState = {
      startClientX: event.clientX,
      startClientY: event.clientY,
      naturalWidth,
      naturalHeight,
      imageRectWidth: imageRect.width,
      imageRectHeight: imageRect.height,
      visibleNaturalWidth,
      visibleNaturalHeight,
      cropNaturalLeft,
      cropNaturalTop
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
    const cropNaturalLeft = this.clamp(
      this.dragState.cropNaturalLeft + ((deltaX / this.dragState.imageRectWidth) * this.dragState.naturalWidth),
      0,
      this.dragState.naturalWidth - this.dragState.visibleNaturalWidth
    )
    const cropNaturalTop = this.clamp(
      this.dragState.cropNaturalTop + ((deltaY / this.dragState.imageRectHeight) * this.dragState.naturalHeight),
      0,
      this.dragState.naturalHeight - this.dragState.visibleNaturalHeight
    )

    const focusX = ((cropNaturalLeft + (this.dragState.visibleNaturalWidth / 2)) / this.dragState.naturalWidth) * 100
    const focusY = ((cropNaturalTop + (this.dragState.visibleNaturalHeight / 2)) / this.dragState.naturalHeight) * 100

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
}

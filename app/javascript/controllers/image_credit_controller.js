import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.sync = this.sync.bind(this)
    this.queueSync = this.queueSync.bind(this)
    this.boundImageLoad = this.queueSync

    this.bindImages()
    this.bindObservers()
    this.queueSync()
  }

  disconnect() {
    this.unbindImages()
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.queueSync)
    this.mutationObserver?.disconnect()
    this.cancelQueuedSync()
  }

  queueSync() {
    this.cancelQueuedSync()
    this.raf = window.requestAnimationFrame(this.sync)
  }

  sync() {
    this.raf = null

    const credit = this.creditElement
    const image = this.activeImage
    if (!credit || !image || credit.hidden || credit.textContent.trim().length === 0) {
      credit?.classList.remove("is-on-image")
      return
    }

    credit.classList.toggle("is-on-image", this.creditOverlapsRenderedImage(credit, image))
  }

  creditOverlapsRenderedImage(credit, image) {
    const imageRect = this.renderedImageRect(image)
    if (!imageRect) return false

    const creditRect = credit.getBoundingClientRect()
    const creditCenterX = creditRect.left + (creditRect.width / 2)
    const creditCenterY = creditRect.top + (creditRect.height / 2)

    return (
      creditCenterX >= imageRect.left &&
      creditCenterX <= imageRect.right &&
      creditCenterY >= imageRect.top &&
      creditCenterY <= imageRect.bottom
    )
  }

  renderedImageRect(image) {
    const { naturalWidth, naturalHeight } = image
    if (!naturalWidth || !naturalHeight) return null

    const box = image.getBoundingClientRect()
    const imageRatio = naturalWidth / naturalHeight
    const boxRatio = box.width / box.height

    if (imageRatio > boxRatio) {
      const renderedHeight = box.width / imageRatio
      const top = box.top + ((box.height - renderedHeight) / 2)

      return {
        left: box.left,
        right: box.right,
        top,
        bottom: top + renderedHeight
      }
    }

    const renderedWidth = box.height * imageRatio
    const left = box.left + ((box.width - renderedWidth) / 2)

    return {
      left,
      right: left + renderedWidth,
      top: box.top,
      bottom: box.bottom
    }
  }

  bindImages() {
    this.imageElements.forEach((image) => {
      if (!image.complete) image.addEventListener("load", this.boundImageLoad)
    })
  }

  unbindImages() {
    this.imageElements.forEach((image) => {
      image.removeEventListener("load", this.boundImageLoad)
    })
  }

  bindObservers() {
    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(this.queueSync)
      this.resizeObserver.observe(this.element)
    } else {
      window.addEventListener("resize", this.queueSync)
    }

    this.mutationObserver = new MutationObserver(this.queueSync)
    this.mutationObserver.observe(this.element, {
      attributes: true,
      attributeFilter: [ "hidden", "class" ],
      childList: true,
      characterData: true,
      subtree: true
    })
  }

  cancelQueuedSync() {
    if (!this.raf) return

    window.cancelAnimationFrame(this.raf)
    this.raf = null
  }

  get creditElement() {
    return this.element.querySelector(".event-detail-image-credit")
  }

  get activeImage() {
    return (
      this.element.querySelector(".event-detail-image-slide.is-current .event-detail-image") ||
      this.element.querySelector(".event-detail-image-stage-static .event-detail-image")
    )
  }

  get imageElements() {
    return Array.from(this.element.querySelectorAll(".event-detail-image"))
  }
}

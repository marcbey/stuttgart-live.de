import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track" ]
  static values = {
    interval: { type: Number, default: 4200 },
    duration: { type: Number, default: 520 }
  }

  connect() {
    this.index = 0
    this.dragStartX = null
    this.dragStartY = null
    this.dragDeltaX = 0
    this.isHorizontalDrag = false
    this.suppressClick = false
    this.handleTransitionEnd = this.handleTransitionEnd.bind(this)
    this.handlePointerDown = this.handlePointerDown.bind(this)
    this.handlePointerMove = this.handlePointerMove.bind(this)
    this.handlePointerUp = this.handlePointerUp.bind(this)
    this.handleClick = this.handleClick.bind(this)
    this.start = this.start.bind(this)
    this.stop = this.stop.bind(this)
    this.advance = this.advance.bind(this)

    if (!this.hasTrackTarget || this.slides.length <= 1) return

    this.appendLoopClone()
    this.trackTarget.addEventListener("transitionend", this.handleTransitionEnd)
    this.trackTarget.addEventListener("pointerdown", this.handlePointerDown)
    this.trackTarget.addEventListener("pointermove", this.handlePointerMove)
    this.trackTarget.addEventListener("pointerup", this.handlePointerUp)
    this.trackTarget.addEventListener("pointercancel", this.handlePointerUp)
    this.trackTarget.addEventListener("click", this.handleClick, true)
    this.element.addEventListener("mouseenter", this.stop)
    this.element.addEventListener("mouseleave", this.start)
    this.element.addEventListener("focusin", this.stop)
    this.element.addEventListener("focusout", this.start)
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) this.start()
  }

  disconnect() {
    this.stop()
    this.trackTarget?.removeEventListener("transitionend", this.handleTransitionEnd)
    this.trackTarget?.removeEventListener("pointerdown", this.handlePointerDown)
    this.trackTarget?.removeEventListener("pointermove", this.handlePointerMove)
    this.trackTarget?.removeEventListener("pointerup", this.handlePointerUp)
    this.trackTarget?.removeEventListener("pointercancel", this.handlePointerUp)
    this.trackTarget?.removeEventListener("click", this.handleClick, true)
    this.element.removeEventListener("mouseenter", this.stop)
    this.element.removeEventListener("mouseleave", this.start)
    this.element.removeEventListener("focusin", this.stop)
    this.element.removeEventListener("focusout", this.start)
    this.loopClone?.remove()
  }

  get slides() {
    return Array.from(this.trackTarget.children).filter((slide) => (
      slide instanceof HTMLElement && slide.dataset.designPreviewClone !== "true"
    ))
  }

  start() {
    if (this.timer) return

    this.timer = window.setTimeout(this.advance, this.currentInterval)
  }

  stop() {
    window.clearTimeout(this.timer)
    this.timer = null
  }

  advance() {
    this.timer = null
    this.index += 1
    this.enableTransition()
    this.moveToIndex(this.index)
    this.start()
  }

  next(event) {
    event?.preventDefault()
    this.stop()
    this.index += 1
    this.enableTransition()
    this.moveToIndex(this.index)
    this.start()
  }

  previous(event) {
    event?.preventDefault()
    this.stop()

    if (this.index <= 0) {
      this.index = this.slides.length
      this.disableTransition()
      this.moveToIndex(this.index)
      this.trackTarget.offsetHeight
    }

    this.index -= 1
    this.enableTransition()
    this.moveToIndex(this.index)
    this.start()
  }

  handlePointerDown(event) {
    if (event.pointerType === "mouse" || event.button !== 0) return

    this.stop()
    this.dragStartX = event.clientX
    this.dragStartY = event.clientY
    this.dragDeltaX = 0
    this.isHorizontalDrag = false
    this.disableTransition()
    this.trackTarget.setPointerCapture?.(event.pointerId)
  }

  handlePointerMove(event) {
    if (this.dragStartX === null) return

    const deltaX = event.clientX - this.dragStartX
    const deltaY = event.clientY - this.dragStartY

    if (!this.isHorizontalDrag && Math.abs(deltaX) < 8) return
    if (!this.isHorizontalDrag && Math.abs(deltaY) > Math.abs(deltaX)) return

    this.isHorizontalDrag = true
    this.dragDeltaX = deltaX
    event.preventDefault()

    const offset = (-this.index * this.trackTarget.clientWidth) + deltaX
    this.trackTarget.style.transform = `translate3d(${offset}px, 0, 0)`
  }

  handlePointerUp(event) {
    if (this.dragStartX === null) return

    const threshold = Math.min(72, this.trackTarget.clientWidth * 0.16)
    const shouldChangeSlide = this.isHorizontalDrag && Math.abs(this.dragDeltaX) >= threshold

    this.trackTarget.releasePointerCapture?.(event.pointerId)
    this.suppressClick = this.isHorizontalDrag
    window.setTimeout(() => { this.suppressClick = false }, 400)
    this.dragStartX = null
    this.dragStartY = null

    if (shouldChangeSlide) {
      this.dragDeltaX < 0 ? this.next() : this.previous()
    } else {
      this.enableTransition()
      this.moveToIndex(this.index)
      this.start()
    }

    this.dragDeltaX = 0
    this.isHorizontalDrag = false
  }

  handleClick(event) {
    if (!this.suppressClick) return

    event.preventDefault()
    event.stopPropagation()
    this.suppressClick = false
  }

  handleTransitionEnd(event) {
    if (event.target !== this.trackTarget || event.propertyName !== "transform") return
    if (this.index < this.slides.length) return

    this.index = 0
    this.disableTransition()
    this.moveToIndex(0)
    this.trackTarget.offsetHeight
    this.enableTransition()
  }

  appendLoopClone() {
    const firstSlide = this.slides[0]
    if (!(firstSlide instanceof HTMLElement)) return

    this.loopClone = firstSlide.cloneNode(true)
    this.loopClone.dataset.designPreviewClone = "true"
    this.loopClone.setAttribute("aria-hidden", "true")
    this.loopClone.querySelectorAll("a, button, input, select, textarea, [tabindex]").forEach((element) => {
      element.setAttribute("tabindex", "-1")
    })
    this.trackTarget.appendChild(this.loopClone)
  }

  moveToIndex(index) {
    this.trackTarget.style.transform = `translate3d(${-100 * index}%, 0, 0)`
  }

  get currentInterval() {
    const slides = this.slides
    const activeSlide = slides[this.index % slides.length]
    const slideInterval = Number(activeSlide?.dataset.designPreviewSlideInterval)

    if (Number.isFinite(slideInterval) && slideInterval > 0) return slideInterval

    return this.intervalValue
  }

  enableTransition() {
    this.trackTarget.style.transition = `transform ${this.durationValue}ms cubic-bezier(0.76, 0, 0.24, 1)`
  }

  disableTransition() {
    this.trackTarget.style.transition = "none"
  }
}

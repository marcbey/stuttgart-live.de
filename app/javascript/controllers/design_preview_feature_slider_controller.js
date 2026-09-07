import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track" ]
  static values = {
    interval: { type: Number, default: 4200 },
    duration: { type: Number, default: 520 }
  }

  connect() {
    this.index = 0
    this.handleTransitionEnd = this.handleTransitionEnd.bind(this)
    this.start = this.start.bind(this)
    this.stop = this.stop.bind(this)
    this.advance = this.advance.bind(this)

    if (!this.hasTrackTarget || this.slides.length <= 1) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.appendLoopClone()
    this.trackTarget.addEventListener("transitionend", this.handleTransitionEnd)
    this.element.addEventListener("mouseenter", this.stop)
    this.element.addEventListener("mouseleave", this.start)
    this.element.addEventListener("focusin", this.stop)
    this.element.addEventListener("focusout", this.start)
    this.start()
  }

  disconnect() {
    this.stop()
    this.trackTarget?.removeEventListener("transitionend", this.handleTransitionEnd)
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

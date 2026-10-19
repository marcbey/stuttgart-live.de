import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track", "toggleButton", "toggleLabel" ]
  static values = {
    interval: { type: Number, default: 4200 },
    duration: { type: Number, default: 520 }
  }

  connect() {
    this.observeViewportOffset()
    this.userPaused = this.userPaused || false
    this.hovered = false
    this.focused = false
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.handleMotionChange = () => {
      this.stop()
      if (this.reduceMotionQuery.matches) {
        this.disableTransition()
        this.moveToIndex(this.index)
      }
      this.updateToggleButton()
      this.start()
    }
    this.handleMouseEnter = () => {
      this.hovered = true
      this.stop()
    }
    this.handleMouseLeave = () => {
      this.hovered = false
      this.start()
    }
    this.handleFocusIn = () => {
      this.focused = true
      this.stop()
    }
    this.handleFocusOut = () => {
      window.requestAnimationFrame(() => {
        this.focused = this.element.contains(document.activeElement)
        this.start()
      })
    }
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
    this.element.addEventListener("mouseenter", this.handleMouseEnter)
    this.element.addEventListener("mouseleave", this.handleMouseLeave)
    this.element.addEventListener("focusin", this.handleFocusIn)
    this.element.addEventListener("focusout", this.handleFocusOut)
    this.reduceMotionQuery.addEventListener("change", this.handleMotionChange)
    this.updateToggleButton()
    this.start()
  }

  disconnect() {
    this.layoutObserver?.disconnect()
    window.removeEventListener("resize", this.updateViewportOffset)
    this.stop()
    if (!this.hasTrackTarget) return

    this.trackTarget.removeEventListener("transitionend", this.handleTransitionEnd)
    this.trackTarget.removeEventListener("pointerdown", this.handlePointerDown)
    this.trackTarget.removeEventListener("pointermove", this.handlePointerMove)
    this.trackTarget.removeEventListener("pointerup", this.handlePointerUp)
    this.trackTarget.removeEventListener("pointercancel", this.handlePointerUp)
    this.trackTarget.removeEventListener("click", this.handleClick, true)
    this.element.removeEventListener("mouseenter", this.handleMouseEnter)
    this.element.removeEventListener("mouseleave", this.handleMouseLeave)
    this.element.removeEventListener("focusin", this.handleFocusIn)
    this.element.removeEventListener("focusout", this.handleFocusOut)
    this.reduceMotionQuery?.removeEventListener("change", this.handleMotionChange)
    this.loopClone?.remove()
  }

  get slides() {
    if (!this.hasTrackTarget) return []

    return Array.from(this.trackTarget.children).filter((slide) => (
      slide instanceof HTMLElement && slide.dataset.designPreviewClone !== "true"
    ))
  }

  observeViewportOffset() {
    if (!document.body.classList.contains("page-public-startpage")) return

    this.updateViewportOffset = () => {
      const top = this.element.getBoundingClientRect().top + window.scrollY
      this.element.style.setProperty("--feature-page-top", `${Math.ceil(top)}px`)
    }
    this.layoutObserver = new ResizeObserver(this.updateViewportOffset)
    document.querySelectorAll(".design-preview-hero, .design-preview-topbar, .design-preview-highlights .design-preview-section-header").forEach((element) => {
      this.layoutObserver.observe(element)
    })
    window.addEventListener("resize", this.updateViewportOffset)
    this.updateViewportOffset()
  }

  start() {
    if (!this.hasTrackTarget || this.slides.length <= 1) return
    if (this.userPaused || this.reduceMotionQuery.matches || this.hovered || this.focused || this.dragStartX !== null) return
    if (this.timer) return

    this.timer = window.setTimeout(this.advance, this.currentInterval)
  }

  toggleAutoplay(event) {
    event.preventDefault()
    if (this.reduceMotionQuery.matches) return

    this.userPaused = !this.userPaused
    this.stop()
    this.updateToggleButton()
    this.start()
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return

    const paused = this.userPaused || this.reduceMotionQuery.matches
    const label = paused ? "Animation starten" : "Animation pausieren"
    this.toggleButtonTarget.classList.toggle("is-paused", paused)
    this.toggleButtonTarget.setAttribute("aria-label", label)
    this.toggleButtonTarget.setAttribute("aria-pressed", paused.toString())
    this.toggleButtonTarget.disabled = this.reduceMotionQuery.matches
    if (this.hasToggleLabelTarget) this.toggleLabelTarget.textContent = label
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
      if (!this.reduceMotionQuery.matches) {
        this.disableTransition()
        this.moveToIndex(this.index)
        this.trackTarget.offsetHeight
      }
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
    const shouldChangeSlide = event.type !== "pointercancel" && this.isHorizontalDrag && Math.abs(this.dragDeltaX) >= threshold

    if (this.trackTarget.hasPointerCapture?.(event.pointerId)) this.trackTarget.releasePointerCapture(event.pointerId)
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
    if (this.reduceMotionQuery.matches && index >= this.slides.length) {
      this.index = 0
      index = 0
    }
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
    if (this.reduceMotionQuery.matches) {
      this.disableTransition()
      return
    }

    this.trackTarget.style.transition = `transform ${this.durationValue}ms cubic-bezier(0.76, 0, 0.24, 1)`
  }

  disableTransition() {
    this.trackTarget.style.transition = "none"
  }
}

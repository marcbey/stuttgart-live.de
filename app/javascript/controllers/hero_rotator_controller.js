import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "slide", "dot", "caption", "credit", "previousButton", "nextButton", "stage" ]
  static values = {
    delay: { type: Number, default: 3000 },
    interval: { type: Number, default: 5000 },
    transitionDuration: { type: Number, default: 320 }
  }

  connect() {
    this.currentIndex = 0
    this.isTransitioning = false
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.handleFocusIn = this.handleFocusIn.bind(this)
    this.handleFocusOut = this.handleFocusOut.bind(this)
    this.handleHeroImageLoad = this.handleHeroImageLoad.bind(this)

    this.element.addEventListener("mouseenter", this.pauseAutoplay)
    this.element.addEventListener("mouseleave", this.resumeAutoplay)
    this.element.addEventListener("focusin", this.handleFocusIn)
    this.element.addEventListener("focusout", this.handleFocusOut)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)

    this.bindHeroStageRatio()
    this.render()
    this.scheduleAutoplay(this.delayValue)
  }

  disconnect() {
    this.clearTimers()
    this.clearTransition()
    this.element.removeEventListener("mouseenter", this.pauseAutoplay)
    this.element.removeEventListener("mouseleave", this.resumeAutoplay)
    this.element.removeEventListener("focusin", this.handleFocusIn)
    this.element.removeEventListener("focusout", this.handleFocusOut)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.unbindHeroStageRatio()
  }

  previous(event) {
    event.preventDefault()
    this.showIndex(this.currentIndex - 1, "previous")
  }

  next(event) {
    event.preventDefault()
    this.showIndex(this.currentIndex + 1, "next")
  }

  select(event) {
    event.preventDefault()
    this.showIndex(Number(event.currentTarget.dataset.heroRotatorIndexParam))
  }

  pauseAutoplay = () => {
    this.isPaused = true
    this.clearTimers()
  }

  resumeAutoplay = () => {
    this.isPaused = false
    this.scheduleAutoplay(this.intervalValue)
  }

  handleFocusIn() {
    this.pauseAutoplay()
  }

  handleFocusOut() {
    window.requestAnimationFrame(() => {
      if (this.element.contains(document.activeElement)) return
      this.resumeAutoplay()
    })
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.clearTimers()
    } else {
      this.scheduleAutoplay(this.intervalValue)
    }
  }

  showIndex(index, direction = null) {
    if (this.slideTargets.length <= 1) return

    const targetIndex = this.normalizeIndex(index)
    if (targetIndex === this.currentIndex || this.isTransitioning) return

    const previousIndex = this.currentIndex
    this.currentIndex = targetIndex
    this.renderDots()
    this.renderMeta()

    if (this.reducedMotion) {
      this.renderSlides()
      this.scheduleAutoplay(this.intervalValue)
      return
    }

    this.animateTransition(previousIndex, targetIndex, direction || this.transitionDirectionFor(targetIndex, previousIndex))
  }

  render() {
    this.renderSlides()
    this.renderDots()
    this.renderMeta()
  }

  renderSlides() {
    this.slideTargets.forEach((slide, index) => {
      const active = index === this.currentIndex
      this.resetSlideState(slide)
      slide.hidden = !active
      slide.tabIndex = active ? 0 : -1
      slide.setAttribute("aria-hidden", active ? "false" : "true")
      if (active) slide.classList.add("is-current")
    })
  }

  renderDots() {
    this.dotTargets.forEach((dot, index) => {
      dot.setAttribute("aria-current", index === this.currentIndex ? "true" : "false")
    })
  }

  renderMeta() {
    const activeSlide = this.slideTargets[this.currentIndex]
    if (!activeSlide) return

    const caption = activeSlide.dataset.heroRotatorCaption || ""
    const credit = activeSlide.dataset.heroRotatorCredit || ""

    if (this.hasCaptionTarget) {
      this.captionTarget.textContent = caption
      this.captionTarget.hidden = caption.length === 0
    }

    if (this.hasCreditTarget) {
      this.creditTarget.textContent = credit
      this.creditTarget.hidden = credit.length === 0
    }
  }

  scheduleAutoplay(delay) {
    this.clearTimers()
    if (this.slideTargets.length <= 1) return
    if (this.reducedMotion || this.isPaused || document.hidden || this.isTransitioning) return

    this.autoplayStartTimer = window.setTimeout(() => {
      this.autoplayTimer = window.setInterval(() => {
        this.showIndex(this.currentIndex + 1, "next")
      }, this.intervalValue)
    }, delay)
  }

  clearTimers() {
    if (this.autoplayStartTimer) {
      window.clearTimeout(this.autoplayStartTimer)
      this.autoplayStartTimer = null
    }

    if (this.autoplayTimer) {
      window.clearInterval(this.autoplayTimer)
      this.autoplayTimer = null
    }
  }

  animateTransition(fromIndex, toIndex, direction) {
    const outgoing = this.slideTargets[fromIndex]
    const incoming = this.slideTargets[toIndex]
    if (!outgoing || !incoming) {
      this.renderSlides()
      this.scheduleAutoplay(this.intervalValue)
      return
    }

    this.clearTimers()
    this.clearTransition()
    this.isTransitioning = true

    this.slideTargets.forEach((slide, index) => {
      this.resetSlideState(slide)
      const visible = index === fromIndex || index === toIndex
      slide.hidden = !visible
      slide.tabIndex = index === toIndex ? 0 : -1
      slide.setAttribute("aria-hidden", index === toIndex ? "false" : "true")
    })

    outgoing.classList.add("is-leaving")
    outgoing.dataset.heroRotatorDirection = direction
    incoming.classList.add("is-entering")
    incoming.dataset.heroRotatorDirection = direction

    const finish = () => {
      this.isTransitioning = false
      this.clearTransition()
      this.renderSlides()
      this.scheduleAutoplay(this.intervalValue)
    }

    const handleTransitionEnd = (event) => {
      if (event.target !== incoming || event.propertyName !== "transform") return
      finish()
    }

    this.transitionCleanup = () => {
      incoming.removeEventListener("transitionend", handleTransitionEnd)
      if (this.transitionTimer) {
        window.clearTimeout(this.transitionTimer)
        this.transitionTimer = null
      }
    }

    incoming.addEventListener("transitionend", handleTransitionEnd)
    this.transitionTimer = window.setTimeout(finish, this.transitionDurationValue + 80)

    window.requestAnimationFrame(() => {
      outgoing.classList.add("is-animating")
      incoming.classList.add("is-animating")
    })
  }

  clearTransition() {
    this.transitionCleanup?.()
    this.transitionCleanup = null
  }

  normalizeIndex(index) {
    const slideCount = this.slideTargets.length
    return (index + slideCount) % slideCount
  }

  transitionDirectionFor(targetIndex, previousIndex) {
    return targetIndex > previousIndex ? "next" : "previous"
  }

  resetSlideState(slide) {
    slide.classList.remove("is-current", "is-entering", "is-leaving", "is-animating")
    delete slide.dataset.heroRotatorDirection
  }

  bindHeroStageRatio() {
    const heroImage = this.heroStageImage
    if (!heroImage) return

    if (heroImage.complete) {
      this.syncHeroStageRatio()
      return
    }

    heroImage.addEventListener("load", this.handleHeroImageLoad)
  }

  unbindHeroStageRatio() {
    this.heroStageImage?.removeEventListener("load", this.handleHeroImageLoad)
  }

  handleHeroImageLoad() {
    this.syncHeroStageRatio()
  }

  syncHeroStageRatio() {
    if (!this.hasStageTarget) return

    const heroImage = this.heroStageImage
    const width = heroImage?.naturalWidth
    const height = heroImage?.naturalHeight
    if (!width || !height) return

    this.element.style.setProperty("--event-detail-image-stage-ratio", `${width} / ${height}`)
    this.element.style.setProperty("--event-detail-image-stage-max-width", `${(32 * width / height).toFixed(4)}rem`)
  }

  get heroStageImage() {
    return this.slideTargets[0]?.querySelector(".event-detail-image")
  }
}

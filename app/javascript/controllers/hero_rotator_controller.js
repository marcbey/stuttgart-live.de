import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "slide", "dot", "caption", "credit", "previousButton", "nextButton", "stage" ]
  static values = {
    delay: { type: Number, default: 3000 },
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.currentIndex = 0
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
    this.element.removeEventListener("mouseenter", this.pauseAutoplay)
    this.element.removeEventListener("mouseleave", this.resumeAutoplay)
    this.element.removeEventListener("focusin", this.handleFocusIn)
    this.element.removeEventListener("focusout", this.handleFocusOut)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.unbindHeroStageRatio()
  }

  previous(event) {
    event.preventDefault()
    this.showIndex(this.currentIndex - 1)
  }

  next(event) {
    event.preventDefault()
    this.showIndex(this.currentIndex + 1)
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

  showIndex(index) {
    if (this.slideTargets.length <= 1) return

    const slideCount = this.slideTargets.length
    this.currentIndex = (index + slideCount) % slideCount
    this.render()
    this.scheduleAutoplay(this.intervalValue)
  }

  render() {
    this.slideTargets.forEach((slide, index) => {
      const active = index === this.currentIndex
      slide.hidden = !active
      slide.tabIndex = active ? 0 : -1
      slide.setAttribute("aria-hidden", active ? "false" : "true")
    })

    this.dotTargets.forEach((dot, index) => {
      dot.setAttribute("aria-current", index === this.currentIndex ? "true" : "false")
    })

    this.renderMeta()
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
    if (this.reducedMotion || this.isPaused || document.hidden) return

    this.autoplayStartTimer = window.setTimeout(() => {
      this.autoplayTimer = window.setInterval(() => {
        this.showIndex(this.currentIndex + 1)
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

    this.stageTarget.style.setProperty("--event-detail-image-stage-ratio", `${width} / ${height}`)
  }

  get heroStageImage() {
    return this.slideTargets[0]?.querySelector(".event-detail-image")
  }
}

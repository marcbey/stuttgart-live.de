import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "logo" ]
  static values = {
    interval: { type: Number, default: 3200 },
    mobileMaxWidth: { type: Number, default: 699 }
  }

  connect() {
    this.currentIndex = 0
    this.handleResize = this.handleResize.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.handleReducedMotionChange = () => this.refresh()

    window.addEventListener("resize", this.handleResize)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    this.reducedMotionQuery.addEventListener("change", this.handleReducedMotionChange)

    this.refresh()
  }

  disconnect() {
    window.removeEventListener("resize", this.handleResize)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.reducedMotionQuery.removeEventListener("change", this.handleReducedMotionChange)
    this.stop()
    this.resetClasses()
    this.element.classList.remove("is-animated")
  }

  refresh() {
    if (this.shouldAnimate()) {
      this.start()
    } else {
      this.stop()
      this.resetClasses()
      this.element.classList.remove("is-animated")
    }
  }

  start() {
    if (this.logoTargets.length <= 1) return
    if (this.timer) return

    this.element.classList.add("is-animated")
    this.showInitialLogo()
    this.timer = window.setInterval(() => this.advance(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  advance() {
    const currentLogo = this.logoTargets[this.currentIndex]
    const nextIndex = (this.currentIndex + 1) % this.logoTargets.length
    const nextLogo = this.logoTargets[nextIndex]

    currentLogo.classList.remove("is-active")
    currentLogo.classList.add("is-exit")

    nextLogo.classList.remove("is-exit")
    window.requestAnimationFrame(() => {
      nextLogo.classList.add("is-active")
    })

    window.setTimeout(() => {
      currentLogo.classList.remove("is-exit")
    }, 520)

    this.currentIndex = nextIndex
  }

  showInitialLogo() {
    if (this.element.classList.contains("is-initialized")) return

    this.resetClasses()
    this.logoTargets[this.currentIndex]?.classList.add("is-active")
    this.element.classList.add("is-initialized")
  }

  resetClasses() {
    this.logoTargets.forEach((logo) => {
      logo.classList.remove("is-active", "is-exit")
    })

    this.element.classList.remove("is-initialized")
  }

  handleResize() {
    this.refresh()
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stop()
      return
    }

    if (this.shouldAnimate()) this.start()
  }

  shouldAnimate() {
    return window.innerWidth <= this.mobileMaxWidthValue && !this.reducedMotionQuery.matches
  }
}

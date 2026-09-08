import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "dateButton", "headerGenres", "headerGenreItem"]

  connect() {
    this.updateChromeState = this.updateChromeState.bind(this)
    this.updateCalendarPosition = this.updateCalendarPosition.bind(this)
    this.updateHeaderGenres = this.updateHeaderGenres.bind(this)

    this.updateChromeState()
    this.updateHeaderGenres()
    window.addEventListener("scroll", this.updateChromeState, { passive: true })
    window.addEventListener("resize", this.updateChromeState)
    window.addEventListener("resize", this.updateHeaderGenres)
    window.addEventListener("scroll", this.updateCalendarPosition, { passive: true })
    window.addEventListener("resize", this.updateCalendarPosition)
    document.fonts?.ready.then(this.updateHeaderGenres)
  }

  disconnect() {
    window.removeEventListener("scroll", this.updateChromeState)
    window.removeEventListener("resize", this.updateChromeState)
    window.removeEventListener("resize", this.updateHeaderGenres)
    window.removeEventListener("scroll", this.updateCalendarPosition)
    window.removeEventListener("resize", this.updateCalendarPosition)
    document.body.classList.remove("is-design-preview-header-scrolled")
    document.body.classList.remove("is-design-preview-header-genres-snapped")
    document.body.style.removeProperty("--design-preview-logo-progress")
    document.body.style.removeProperty("--design-preview-logo-hero-y")
    document.body.style.removeProperty("--design-preview-logo-hero-scale")
    document.body.style.removeProperty("--design-preview-logo-header-y")
    document.body.style.removeProperty("--design-preview-logo-header-scale")
  }

  openDate() {
    const calendarButton = this.element.querySelector("[data-public-search-target='calendarButton']")
    if (!(calendarButton instanceof HTMLButtonElement)) return

    calendarButton.click()
    window.requestAnimationFrame(this.updateCalendarPosition)
  }

  dismiss(event) {
    event.preventDefault()

    if (this.hasBarTarget) {
      this.barTarget.hidden = true
    }
  }

  updateChromeState() {
    const logoProgress = Math.min(1, Math.max(0, window.scrollY / 88))

    document.body.classList.toggle("is-design-preview-header-scrolled", window.scrollY > 8)
    document.body.classList.toggle("is-design-preview-header-genres-snapped", this.headerGenresShouldSnap)
    document.body.style.setProperty("--design-preview-logo-progress", logoProgress.toFixed(3))
    document.body.style.setProperty("--design-preview-logo-hero-y", `${(-2.6 * logoProgress).toFixed(3)}rem`)
    document.body.style.setProperty("--design-preview-logo-hero-scale", (1 - 0.18 * logoProgress).toFixed(3))
    document.body.style.setProperty("--design-preview-logo-header-y", `${(1.1 * (1 - logoProgress)).toFixed(3)}rem`)
    document.body.style.setProperty("--design-preview-logo-header-scale", (1 + 0.28 * (1 - logoProgress)).toFixed(3))
    this.updateCalendarPosition()
    window.requestAnimationFrame(this.updateHeaderGenres)
  }

  updateHeaderGenres() {
    if (!this.hasHeaderGenresTarget) return
    if (window.getComputedStyle(this.headerGenresTarget).display === "none") return

    const more = this.headerGenresTarget.querySelector(".design-preview-header-genres-more")
    if (!(more instanceof HTMLElement)) return

    more.hidden = false
    this.headerGenreItemTargets.forEach((item) => {
      item.hidden = false
    })
  }

  get headerGenresShouldSnap() {
    const topbar = this.element.querySelector(".design-preview-topbar")
    if (!(topbar instanceof HTMLElement)) return false

    if (window.scrollY > 40) return true

    if (!this.hasBarTarget || this.barTarget.hidden) return false

    return this.barTarget.getBoundingClientRect().top <= topbar.getBoundingClientRect().bottom + 6
  }

  updateCalendarPosition() {
    const panel = this.element.querySelector("[data-public-search-target='calendarPanel']")
    if (!(panel instanceof HTMLElement)) return

    if (panel.hidden || !this.hasDateButtonTarget) {
      panel.style.removeProperty("position")
      panel.style.removeProperty("top")
      panel.style.removeProperty("left")
      panel.style.removeProperty("right")
      panel.style.removeProperty("width")
      return
    }

    const buttonRect = this.dateButtonTarget.getBoundingClientRect()
    const width = Math.min(296, window.innerWidth - 32)
    const left = Math.max(16, Math.min(buttonRect.left, window.innerWidth - width - 16))

    panel.style.position = "fixed"
    panel.style.top = `${buttonRect.bottom + 8}px`
    panel.style.left = `${left}px`
    panel.style.right = "auto"
    panel.style.width = `${width}px`
  }
}

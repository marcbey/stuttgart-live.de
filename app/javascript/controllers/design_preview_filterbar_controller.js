import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "dateButton", "viewDock", "viewHome", "viewSwitch", "homepageBar"]
  static values = { destination: String }

  connect() {
    this.updateChromeState = this.updateChromeState.bind(this)
    this.updateCalendarPosition = this.updateCalendarPosition.bind(this)
    this.handleCalendarSelection = this.handleCalendarSelection.bind(this)
    this.handleCalendarEscape = this.handleCalendarEscape.bind(this)
    this.resetActiveCalendarIfClosed = this.resetActiveCalendarIfClosed.bind(this)
    this.activeCalendarForm = null
    this.restoreViewSwitch = () => this.moveViewSwitch(false)

    this.updateChromeState()
    window.addEventListener("scroll", this.updateChromeState, { passive: true })
    window.addEventListener("resize", this.updateChromeState)
    window.addEventListener("scroll", this.updateCalendarPosition, { passive: true })
    window.addEventListener("resize", this.updateCalendarPosition)
    this.element.addEventListener("public-search:calendar-selected", this.handleCalendarSelection)
    this.element.addEventListener("public-search:calendar-closed", this.resetActiveCalendarIfClosed)
    document.addEventListener("keydown", this.handleCalendarEscape)
    document.addEventListener("turbo:before-cache", this.restoreViewSwitch)
  }

  disconnect() {
    window.removeEventListener("scroll", this.updateChromeState)
    window.removeEventListener("resize", this.updateChromeState)
    window.removeEventListener("scroll", this.updateCalendarPosition)
    window.removeEventListener("resize", this.updateCalendarPosition)
    this.element.removeEventListener("public-search:calendar-selected", this.handleCalendarSelection)
    this.element.removeEventListener("public-search:calendar-closed", this.resetActiveCalendarIfClosed)
    document.removeEventListener("keydown", this.handleCalendarEscape)
    document.removeEventListener("turbo:before-cache", this.restoreViewSwitch)
    this.restoreViewSwitch()
    document.body.classList.remove("is-design-preview-header-scrolled")
    document.body.classList.remove("is-design-preview-header-genres-snapped")
    document.body.style.removeProperty("--design-preview-logo-progress")
    document.body.style.removeProperty("--design-preview-logo-hero-y")
    document.body.style.removeProperty("--design-preview-logo-hero-scale")
    document.body.style.removeProperty("--design-preview-logo-header-y")
    document.body.style.removeProperty("--design-preview-logo-header-scale")
  }

  openDate(event) {
    event?.preventDefault()

    const calendarButton = this.visibleSearchCalendarButton
    if (!(calendarButton instanceof HTMLButtonElement)) return

    this.activeCalendarForm = calendarButton.closest("[data-controller~='public-search']")
    const calendar = this.activeCalendarController
    if (!calendar) return
    if (!this.activeCalendarPanel.hidden) {
      calendar.closeCalendar()
      return
    }

    const params = new URL(window.location.href).searchParams
    this.activeCalendarPanel.dataset.designPreviewFilterbarCalendar = "true"
    calendar.openCalendar({
      selection: { start: params.get("event_date"), end: params.get("event_date_end") },
      mode: params.has("event_date_end") ? "range" : "day",
      trigger: event.currentTarget
    })
    window.requestAnimationFrame(this.updateCalendarPosition)
  }

  handleCalendarSelection(event) {
    if (event.target !== this.activeCalendarForm || this.activeCalendarPanel?.dataset.designPreviewFilterbarCalendar !== "true") return
    event.preventDefault()
    this.navigateToDate(event.detail.start, event.detail.end)
  }

  handleCalendarEscape(event) {
    if (event.key === "Escape") {
      window.requestAnimationFrame(this.resetActiveCalendarIfClosed)
    }
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
    this.updateViewSwitch()
    this.updateHomepageBar()
  }

  updateHomepageBar() {
    if (!this.hasHomepageBarTarget) return

    const hidden = window.scrollY <= 88
    if (this.homepageBarTarget.hidden === hidden) return

    this.homepageBarTarget.hidden = hidden
    if (hidden) {
      this.homepageBarTarget.querySelectorAll("details[open]").forEach((dropdown) => { dropdown.open = false })
      this.activeCalendarController?.closeCalendar()
    }
  }

  updateViewSwitch() {
    if (!this.hasViewDockTarget) return

    const stickyTop = Number.parseFloat(window.getComputedStyle(this.viewDockTarget).top)
    const docked = window.matchMedia("(min-width: 48rem)").matches &&
      this.viewDockTarget.getBoundingClientRect().top <= stickyTop + 1
    this.moveViewSwitch(docked)
  }

  moveViewSwitch(docked) {
    if (!this.hasViewSwitchTarget || !this.hasViewHomeTarget || !this.hasViewDockTarget) return

    const destination = docked ? this.viewDockTarget : this.viewHomeTarget
    this.viewDockTarget.classList.toggle("has-docked-view", docked)
    if (this.viewSwitchTarget.parentElement === destination) return

    const focusedElement = this.viewSwitchTarget.contains(document.activeElement) ? document.activeElement : null
    destination.append(this.viewSwitchTarget)
    focusedElement?.focus({ preventScroll: true })
  }

  get headerGenresShouldSnap() {
    const topbar = this.element.querySelector(".design-preview-topbar")
    if (!(topbar instanceof HTMLElement)) return false

    if (window.scrollY > 8) return true

    if (!this.hasBarTarget || this.barTarget.hidden) return false

    return this.barTarget.getBoundingClientRect().top <= topbar.getBoundingClientRect().bottom + 6
  }

  updateCalendarPosition() {
    const panel = this.activeCalendarPanel
    if (!(panel instanceof HTMLElement)) return

    if (panel.hidden || panel.dataset.designPreviewFilterbarCalendar !== "true" || !this.hasDateButtonTarget) {
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

  navigateToDate(dateKey, endDateKey = dateKey) {
    const url = new URL(this.destinationValue || window.location.href, window.location.origin)

    url.searchParams.set("event_date", dateKey)
    if (endDateKey !== dateKey) {
      url.searchParams.set("event_date_end", endDateKey)
      url.searchParams.delete("event_month")
    } else {
      url.searchParams.delete("event_date_end")
      url.searchParams.set("event_month", dateKey.slice(0, 7))
    }
    url.searchParams.delete("page")
    url.searchParams.delete("cursor")
    url.searchParams.delete("q")

    window.location.assign(url.toString())
  }

  resetActiveCalendarIfClosed() {
    this.calendarPanels.forEach((panel) => {
      if (panel.hidden) {
        delete panel.dataset.designPreviewFilterbarCalendar
        Object.assign(panel.style, { position: "", top: "", left: "", right: "", width: "" })
      }
    })

    const activePanel = this.calendarPanels.find((panel) => panel.dataset.designPreviewFilterbarCalendar === "true")
    if (!activePanel) {
      this.activeCalendarForm = null
    }
  }

  get activeCalendarPanel() {
    const activePanel = this.activeCalendarForm?.querySelector("[data-public-search-target='calendarPanel']")
    if (activePanel instanceof HTMLElement) return activePanel

    return this.element.querySelector("[data-public-search-target='calendarPanel']")
  }

  get activeCalendarController() {
    if (!this.activeCalendarForm) return null
    return this.application.getControllerForElementAndIdentifier(this.activeCalendarForm, "public-search")
  }

  get visibleSearchCalendarButton() {
    return this.searchCalendarButtons.find((button) => this.toolbarIsVisible(button)) || this.searchCalendarButtons[0]
  }

  get searchCalendarButtons() {
    return Array.from(this.element.querySelectorAll("[data-public-search-target='calendarButton']"))
      .filter((button) => button instanceof HTMLButtonElement)
  }

  get calendarPanels() {
    return Array.from(this.element.querySelectorAll("[data-public-search-target='calendarPanel']"))
      .filter((panel) => panel instanceof HTMLElement)
  }

  toolbarIsVisible(button) {
    const toolbar = button.closest(".design-preview-mobile-toolbar, .design-preview-header-toolbar")
    if (!(toolbar instanceof HTMLElement)) return true

    const style = window.getComputedStyle(toolbar)

    return style.display !== "none" && style.visibility !== "hidden"
  }
}

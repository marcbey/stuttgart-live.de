import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "monthButton", "monthPanel", "dayButton", "dayPanel", "timeHint" ]

  closeOutside(event) {
    const disclosure = this.element.closest("details")
    if (!disclosure?.open || disclosure.contains(event.target)) return

    disclosure.open = false
  }

  selectMonth(event) {
    event.preventDefault()

    this.showMonth(event.params.monthKey)
    this.showDay(event.params.dayKey)
  }

  selectDay(event) {
    event.preventDefault()

    const times = this.showDay(event.params.dayKey)
    if (times.length === 1) times[0].click()
  }

  showMonth(monthKey) {
    this.monthButtonTargets.forEach((button) => {
      const active = button.dataset.eventSeriesCalendarMonthKeyParam === monthKey
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })

    this.monthPanelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.monthKey !== monthKey
    })
  }

  showDay(dayKey) {
    const selectedPanel = this.dayPanelTargets.find((panel) => panel.dataset.dayKey === dayKey)
    const times = selectedPanel?.querySelectorAll(".event-series-calendar-time") || []

    this.timeHintTargets.forEach((hint) => {
      hint.hidden = times.length < 2
      hint.textContent = times.length >= 2 ? "Uhrzeit wählen" : ""
    })

    this.dayButtonTargets.forEach((button) => {
      const active = button.dataset.eventSeriesCalendarDayKeyParam === dayKey
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })

    this.dayPanelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.dayKey !== dayKey
    })

    return times
  }
}

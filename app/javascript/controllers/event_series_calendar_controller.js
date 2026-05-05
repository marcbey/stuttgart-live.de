import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "monthButton", "monthPanel", "dayButton", "dayPanel" ]

  selectMonth(event) {
    event.preventDefault()

    this.showMonth(event.params.monthKey)
    this.showDay(event.params.dayKey)
  }

  selectDay(event) {
    event.preventDefault()

    this.showDay(event.params.dayKey)
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
    this.dayButtonTargets.forEach((button) => {
      const active = button.dataset.eventSeriesCalendarDayKeyParam === dayKey
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })

    this.dayPanelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.dayKey !== dayKey
    })
  }
}

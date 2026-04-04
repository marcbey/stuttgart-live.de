import { Controller } from "@hotwired/stimulus"

const RESTORE_SCROLL_KEY = "history-back-link:restore-scroll"

export default class extends Controller {
  navigate(event) {
    if (!this.shouldUseHistoryBack()) return

    event.preventDefault()
    window.sessionStorage.setItem(RESTORE_SCROLL_KEY, "true")
    window.history.back()
  }

  shouldUseHistoryBack() {
    if (window.history.length <= 1) return false
    if (!document.referrer) return false

    try {
      const referrer = new URL(document.referrer)
      const currentLocation = new URL(window.location.href)

      return referrer.origin === currentLocation.origin &&
        `${referrer.pathname}${referrer.search}` !== `${currentLocation.pathname}${currentLocation.search}`
    } catch {
      return false
    }
  }
}

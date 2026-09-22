import { Controller } from "@hotwired/stimulus"

const RESTORE_SCROLL_KEY = "history-back-link:restore-scroll"
const NAVIGATION_TRANSITION_KEY = "history-back-link:navigation-transition"

document.addEventListener("turbo:before-visit", (event) => {
  const destination = new URL(event.detail.url, window.location.href)

  window.sessionStorage.setItem(NAVIGATION_TRANSITION_KEY, JSON.stringify({
    from: window.location.href,
    to: destination.href
  }))
})

export default class extends Controller {
  navigate(event) {
    if (!this.shouldUseHistoryBack()) return

    event.preventDefault()
    window.sessionStorage.setItem(RESTORE_SCROLL_KEY, "true")
    window.history.back()
  }

  shouldUseHistoryBack() {
    if (window.history.length <= 1) return false

    try {
      const currentLocation = new URL(window.location.href)

      return this.hasInternalReferrer(currentLocation) || this.hasTrackedInternalNavigation(currentLocation)
    } catch {
      return false
    }
  }

  hasInternalReferrer(currentLocation) {
    if (!document.referrer) return false

    const referrer = new URL(document.referrer)

    return referrer.origin === currentLocation.origin &&
      this.locationKey(referrer) !== this.locationKey(currentLocation)
  }

  hasTrackedInternalNavigation(currentLocation) {
    const transition = JSON.parse(window.sessionStorage.getItem(NAVIGATION_TRANSITION_KEY) || "null")
    if (!transition?.from || !transition?.to) return false

    const from = new URL(transition.from)
    const to = new URL(transition.to)

    return from.origin === currentLocation.origin &&
      to.origin === currentLocation.origin &&
      this.locationKey(to) === this.locationKey(currentLocation) &&
      this.locationKey(from) !== this.locationKey(currentLocation)
  }

  locationKey(location) {
    return `${location.pathname}${location.search}`
  }
}

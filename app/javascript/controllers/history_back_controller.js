import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    fallbackUrl: String,
    samePathOnly: Boolean
  }

  navigate(event) {
    if (!this.shouldUseHistoryBack()) return

    event.preventDefault()
    window.history.back()
  }

  shouldUseHistoryBack() {
    if (window.history.length <= 1) return false
    if (!this.hasFallbackUrlValue) return false
    if (document.referrer.length === 0) return false

    const referrerUrl = this.parseUrl(document.referrer)
    const fallbackUrl = this.parseUrl(this.fallbackUrlValue)

    if (!referrerUrl || !fallbackUrl) return false
    if (referrerUrl.origin !== window.location.origin) return false
    if (this.samePathOnlyValue && referrerUrl.pathname !== fallbackUrl.pathname) return false

    return true
  }

  parseUrl(value) {
    try {
      return new URL(value, window.location.origin)
    } catch {
      return null
    }
  }
}

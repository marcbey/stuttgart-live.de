import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "stuttgart-live-consent-v1"
const CONSENT_EVENT = "stuttgart-live:consent-changed"
const DEFAULT_PREFERENCES = {
  analytics: false,
  media: false
}

export default class extends Controller {
  static targets = ["banner", "dialog", "panel", "analyticsInput", "mediaInput", "closeButton"]
  static values = { measurementId: String }

  connect() {
    this.trackPageView = this.trackPageView.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)

    this.ensureGoogleTag()

    this.preferences = this.loadPreferences()
    this.applyConsent(this.preferences, { persist: false, announce: true })

    document.addEventListener("turbo:load", this.trackPageView)
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.trackPageView)
    document.removeEventListener("keydown", this.handleKeydown)
    this.toggleBackgroundInert(false)
    document.body.classList.remove("consent-dialog-open")
  }

  openSettings(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget) return

    this.lastFocusedElement = document.activeElement instanceof HTMLElement ? document.activeElement : null
    this.syncInputs()
    this.dialogTarget.hidden = false
    document.body.classList.add("consent-dialog-open")
    this.toggleBackgroundInert(true)
    document.addEventListener("keydown", this.handleKeydown)
    window.requestAnimationFrame(() => this.focusFirstElement())
  }

  closeSettings(event) {
    if (event?.type === "click" && event.target !== event.currentTarget) return
    if (!this.hasDialogTarget) return

    this.dialogTarget.hidden = true
    document.body.classList.remove("consent-dialog-open")
    document.removeEventListener("keydown", this.handleKeydown)
    this.toggleBackgroundInert(false)
    this.restoreFocus()
  }

  acceptAll(event) {
    event.preventDefault()
    this.persistAndClose({ analytics: true, media: true })
  }

  acceptEssential(event) {
    event.preventDefault()
    this.persistAndClose(DEFAULT_PREFERENCES)
  }

  acceptMedia(event) {
    event.preventDefault()
    this.persistAndClose({ ...this.preferences, media: true })
  }

  savePreferences(event) {
    event.preventDefault()

    this.persistAndClose({
      analytics: this.hasAnalyticsInputTarget ? this.analyticsInputTarget.checked : false,
      media: this.hasMediaInputTarget ? this.mediaInputTarget.checked : false
    })
  }

  trackPageView() {
    if (!this.analyticsEnabled()) return

    const currentLocation = `${window.location.pathname}${window.location.search}`
    if (window.StuttgartLiveLastTrackedLocation === currentLocation) return

    window.gtag("event", "page_view", {
      page_title: document.title,
      page_location: window.location.href,
      page_path: currentLocation
    })

    window.StuttgartLiveLastTrackedLocation = currentLocation
  }

  persistAndClose(preferences) {
    this.applyConsent(preferences, { persist: true, announce: true })
    this.closeSettings()
  }

  applyConsent(preferences, { persist, announce }) {
    this.preferences = this.normalizePreferences(preferences)

    if (persist) {
      this.storePreferences(this.preferences)
    }

    this.updateBanner()
    this.syncInputs()
    this.updateConsentMode()
    this.updateAnalytics()
    window.StuttgartLiveConsent = { preferences: this.preferences }

    if (announce) {
      window.dispatchEvent(new CustomEvent(CONSENT_EVENT, { detail: { preferences: this.preferences } }))
    }
  }

  normalizePreferences(preferences) {
    return {
      analytics: preferences?.analytics === true,
      media: preferences?.media === true
    }
  }

  loadPreferences() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      return raw ? this.normalizePreferences(JSON.parse(raw)) : DEFAULT_PREFERENCES
    } catch (_error) {
      return DEFAULT_PREFERENCES
    }
  }

  storePreferences(preferences) {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(preferences))
    } catch (_error) {
      // Ignore storage failures and keep the in-memory preference state.
    }
  }

  hasStoredPreferences() {
    try {
      return window.localStorage.getItem(STORAGE_KEY) !== null
    } catch (_error) {
      return false
    }
  }

  updateBanner() {
    if (!this.hasBannerTarget) return

    this.bannerTarget.hidden = this.hasStoredPreferences()
  }

  syncInputs() {
    if (this.hasAnalyticsInputTarget) {
      this.analyticsInputTarget.checked = this.preferences.analytics
    }

    if (this.hasMediaInputTarget) {
      this.mediaInputTarget.checked = this.preferences.media
    }
  }

  handleKeydown(event) {
    if (this.dialogTarget.hidden) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.closeSettings()
      return
    }

    if (event.key !== "Tab") return

    const focusableElements = this.focusableElements()
    if (focusableElements.length === 0) {
      event.preventDefault()
      this.panelTarget?.focus()
      return
    }

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault()
      lastElement.focus()
    } else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  focusFirstElement() {
    const [firstElement] = this.focusableElements()
    ;(firstElement || this.closeButtonTarget || this.panelTarget)?.focus()
  }

  restoreFocus() {
    if (this.lastFocusedElement?.isConnected) {
      this.lastFocusedElement.focus()
    }
  }

  focusableElements() {
    const root = this.hasPanelTarget ? this.panelTarget : this.dialogTarget
    if (!root) return []

    return Array.from(root.querySelectorAll(this.focusableSelector())).filter((element) => {
      if (!(element instanceof HTMLElement)) return false
      if (element.hidden || element.getAttribute("aria-hidden") === "true") return false
      return !element.hasAttribute("disabled")
    })
  }

  focusableSelector() {
    return [
      "a[href]",
      "button:not([disabled])",
      "input:not([disabled])",
      "select:not([disabled])",
      "textarea:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")
  }

  toggleBackgroundInert(inert) {
    Array.from(document.body.children).forEach((element) => {
      if (element === this.dialogTarget) return
      if (!(element instanceof HTMLElement)) return
      element.inert = inert
    })
  }

  ensureGoogleTag() {
    window.dataLayer = window.dataLayer || []
    window.gtag = window.gtag || function gtag() {
      window.dataLayer.push(arguments)
    }

    if (window.StuttgartLiveConsentModeInitialized) return

    window.gtag("consent", "default", this.googleConsentState(DEFAULT_PREFERENCES))
    window.StuttgartLiveConsentModeInitialized = true
  }

  updateConsentMode() {
    window.gtag("consent", "update", this.googleConsentState(this.preferences))
  }

  googleConsentState(preferences) {
    return {
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
      analytics_storage: preferences.analytics ? "granted" : "denied",
      functionality_storage: preferences.media ? "granted" : "denied",
      personalization_storage: "denied",
      security_storage: "granted"
    }
  }

  analyticsEnabled() {
    return this.hasMeasurementIdValue && this.measurementIdValue.length > 0 && this.preferences.analytics
  }

  updateAnalytics() {
    if (!this.hasMeasurementIdValue) return

    const disabledKey = `ga-disable-${this.measurementIdValue}`
    window[disabledKey] = !this.preferences.analytics

    if (!this.preferences.analytics) return

    this.loadAnalyticsScript()
    this.configureAnalytics()
    this.trackPageView()
  }

  loadAnalyticsScript() {
    if (
      window.StuttgartLiveGaScriptRequested ||
      document.querySelector(`[data-google-analytics-tag="${this.measurementIdValue}"]`)
    ) {
      return
    }

    window.StuttgartLiveGaScriptRequested = true

    const script = document.createElement("script")
    script.async = true
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(this.measurementIdValue)}`
    script.dataset.googleAnalyticsTag = this.measurementIdValue
    document.head.appendChild(script)
  }

  configureAnalytics() {
    if (window.StuttgartLiveGaConfiguredId === this.measurementIdValue) return

    window.gtag("js", new Date())
    window.gtag("config", this.measurementIdValue, {
      anonymize_ip: true,
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      send_page_view: false
    })

    window.StuttgartLiveGaConfiguredId = this.measurementIdValue
  }
}

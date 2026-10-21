const startedDocuments = new WeakSet()
const metricNames = ["CLS", "FCP", "INP", "LCP", "TTFB"]
const navigationTypes = new Set(["navigate", "reload", "back-forward", "back-forward-cache", "prerender", "restore"])

// Metadata contains Rails route templates, never resolved paths or query strings.
function context(document, window) {
  const meta = name => document.querySelector(`meta[name="${name}"]`)?.content
  const route = meta("web-vitals-route")
  const release = meta("web-vitals-release")
  return {
    route: typeof route === "string" && /^\/[a-zA-Z0-9_/:*().-]*$/.test(route) ? route : "/unknown",
    release: /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(release || "") ? release : "unknown",
    device: window.matchMedia("(max-width: 767px)").matches ? "mobile" :
      (window.matchMedia("(max-width: 1023px)").matches ? "tablet" : "desktop")
  }
}

export function startWebVitals({ window = globalThis.window, document = globalThis.document,
  loadVitals = () => import("web-vitals") } = {}) {
  if (startedDocuments.has(document) || !document.body?.classList.contains("page-public") ||
      !document.querySelector('meta[name="web-vitals-route"]')) return
  startedDocuments.add(document)

  // Capture before the first Turbo visit, including when consent arrives much later.
  const documentContext = context(document, window)
  const restorations = new Map()
  window.addEventListener("pageshow", event => {
    if (event.persisted) restorations.set(event.timeStamp, context(document, window))
  }, true)

  const target = () => {
    const id = document.body?.dataset.consentMeasurementIdValue
    return document.body?.classList.contains("page-public") &&
      window.StuttgartLiveConsent?.preferences?.analytics === true &&
      /^G-[A-Z0-9]+$/.test(id || "") && window.StuttgartLiveGaConfiguredId === id &&
      window[`ga-disable-${id}`] === false && typeof window.gtag === "function" ? id : null
  }

  const report = metric => {
    const id = target()
    if (!id || !metricNames.includes(metric.name) || !Number.isFinite(metric.value) || metric.value < 0 ||
        !Number.isFinite(metric.delta) || !/^v6-\d{13}-\d{13}$/.test(metric.id) ||
        !navigationTypes.has(metric.navigationType)) return
    // v6 forwards the hard-navigation URL through BFCache; navigationStartTime
    // identifies the persisted pageshow instead. Never use callback-time location.
    const visit = metric.navigationType === "back-forward-cache" ? restorations.get(metric.navigationStartTime) : documentContext
    if (!visit) return
    window.gtag("event", "web_vital", {
      send_to: id, metric_name: metric.name, value: metric.delta, metric_value: metric.value,
      metric_unit: metric.name === "CLS" ? "score" : "ms", metric_id: metric.id,
      device_segment: visit.device, route_pattern: visit.route, release: visit.release,
      navigation_type: metric.navigationType,
      // Event-local overrides prevent inheritance of GA's full URL/title/referrer.
      page_location: visit.route, page_path: visit.route, page_title: "", page_referrer: ""
    })
  }

  let pending = false
  let registered = false
  const enable = async () => {
    if (pending || registered || !target() || typeof window.PerformanceObserver !== "function") return
    pending = true
    try {
      const vitals = await loadVitals()
      if (!target()) return
      registered = true
      for (const name of metricNames) {
        vitals[`on${name}`]?.(report, { reportAllChanges: true, reportSoftNavs: false })
      }
    } catch (_error) {
      // Unsupported APIs or a failed chunk must never interrupt consent or navigation.
    } finally {
      pending = false
    }
  }
  window.addEventListener("stuttgart-live:consent-changed", enable)
  enable()
}

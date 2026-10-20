import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = await readFile(new URL("../../app/javascript/public/web_vitals.js", import.meta.url), "utf8")
const { startWebVitals } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)
const names = ["CLS", "FCP", "INP", "LCP", "TTFB"]
const flush = () => new Promise(resolve => setImmediate(resolve))

function browser({ consent = false, target = "G-TEST123", route = "/events/:slug", release = "a".repeat(40), supported = true } = {}) {
  const window = new EventTarget()
  Object.assign(window, {
    StuttgartLiveConsent: { preferences: { analytics: consent } }, StuttgartLiveGaConfiguredId: target,
    [`ga-disable-${target}`]: false, PerformanceObserver: supported ? class {} : undefined,
    matchMedia: query => ({ matches: query === "(max-width: 767px)" }),
    gtag: (...args) => reports.push(args)
  })
  const metadata = { "web-vitals-route": route, "web-vitals-release": release }
  const document = { body: { classList: { contains: name => name === "page-public" }, dataset: { consentMeasurementIdValue: target } },
    querySelector: selector => ({ content: metadata[selector.match(/name="([^"]+)"/)[1]] }) }
  const reports = [], registrations = [], callbacks = {}
  let imports = 0
  const vitals = Object.fromEntries(names.map(name => [`on${name}`, (callback, opts) => {
    callbacks[name] = callback
    registrations.push([name, opts])
  }]))
  const loadVitals = async () => { imports++; return vitals }
  const start = (loader = loadVitals) => startWebVitals({ window, document, loadVitals: loader })
  const changeConsent = value => {
    window.StuttgartLiveConsent.preferences.analytics = value
    window.dispatchEvent(new Event("stuttgart-live:consent-changed"))
  }
  const metric = (name = "LCP", extra = {}) => ({ name, value: 142.5, delta: 42.5, id: "v6-1234567890123-1234567890123",
    navigationType: "navigate", navigationURL: "https://example.com/events/private-name?q=secret", navigationStartTime: 0,
    entries: [{ element: { textContent: "private" } }], ...extra })
  return { window, document, metadata, reports, registrations, callbacks, vitals, start, changeConsent, metric, get imports() { return imports } }
}

test("denied or missing configured target never imports; existing gtag is insufficient", async () => {
  for (const options of [{}, { consent: true, target: "" }, { consent: true, supported: false }]) {
    const b = browser(options); b.start(); await flush(); assert.equal(b.imports, 0)
  }
  const b = browser({ consent: true }); b.window.StuttgartLiveGaConfiguredId = "G-OTHER"; b.start(); await flush(); assert.equal(b.imports, 0)
})

test("saved and newly granted consent register all five metrics once per document, without soft navs", async () => {
  for (const consent of [true, false]) {
    const b = browser({ consent }); b.start(); b.changeConsent(true); b.start(); await flush()
    assert.equal(b.imports, 1)
    assert.deepEqual(b.registrations.map(([name]) => name), names)
    assert.ok(b.registrations.every(([, opts]) => opts.reportSoftNavs === false && opts.reportAllChanges === true))
    b.window.dispatchEvent(new Event("turbo:load")); b.changeConsent(true); await flush(); assert.equal(b.imports, 1)
  }
})

test("revocation while import is pending prevents observer registration; regrant can register", async () => {
  const b = browser({ consent: true }); let resolve
  b.start(() => new Promise(done => { resolve = done }))
  b.changeConsent(false); resolve(b.vitals); await flush(); assert.equal(b.registrations.length, 0)
  b.changeConsent(true); resolve(b.vitals); await flush(); assert.equal(b.registrations.length, 5)
})

test("every callback rechecks consent, current public surface and the configured GA target", async () => {
  const b = browser({ consent: true }); b.start(); await flush()
  b.callbacks.LCP(b.metric()); assert.equal(b.reports.length, 1)
  b.changeConsent(false); b.callbacks.LCP(b.metric()); assert.equal(b.reports.length, 1)
  b.changeConsent(true); b.window["ga-disable-G-TEST123"] = true; b.callbacks.LCP(b.metric()); assert.equal(b.reports.length, 1)
  b.window["ga-disable-G-TEST123"] = false; b.window.StuttgartLiveGaConfiguredId = "G-OTHER"; b.callbacks.LCP(b.metric()); assert.equal(b.reports.length, 1)
  b.window.StuttgartLiveGaConfiguredId = "G-TEST123"; b.document.body.classList.contains = () => false
  b.callbacks.LCP(b.metric()); assert.equal(b.reports.length, 1)
})

test("payload projects only numeric metrics and safe metadata and overrides inherited GA page context", async () => {
  const b = browser({ consent: true }); b.start(); await flush()
  for (const name of names) b.callbacks[name](b.metric(name))
  assert.equal(b.reports.length, 5)
  assert.deepEqual(b.reports[3], ["event", "web_vital", {
    send_to: "G-TEST123", metric_name: "LCP", value: 42.5, metric_value: 142.5, metric_unit: "ms",
    metric_id: "v6-1234567890123-1234567890123", device_segment: "mobile", route_pattern: "/events/:slug",
    release: "a".repeat(40), navigation_type: "navigate", page_location: "/events/:slug", page_path: "/events/:slug", page_title: "", page_referrer: ""
  }])
  assert.equal(b.reports[0][2].metric_unit, "score")
  assert.doesNotMatch(JSON.stringify(b.reports), /private|secret|example\.com|entries|element/)
})

test("repeated metric IDs preserve signed deltas and latest total for distribution aggregation", async () => {
  const b = browser({ consent: true }); b.start(); await flush()
  b.callbacks.INP(b.metric("INP", { value: 200, delta: 200 }))
  b.callbacks.INP(b.metric("INP", { value: 120, delta: -80 }))
  assert.deepEqual(b.reports.map(report => [report[2].metric_id, report[2].value, report[2].metric_value]), [
    ["v6-1234567890123-1234567890123", 200, 200], ["v6-1234567890123-1234567890123", -80, 120]
  ])
})

test("first consent after Turbo and delayed reports retain the original document context", async () => {
  const b = browser(); b.start(); b.metadata["web-vitals-route"] = "/news/:slug"
  b.window.dispatchEvent(new Event("turbo:load")); b.changeConsent(true); await flush()
  b.callbacks.LCP(b.metric()); assert.equal(b.reports[0][2].route_pattern, "/events/:slug")
})

test("BFCache restoration keeps its route for new IDs even after later Turbo and for delayed old metrics", async () => {
  const b = browser({ consent: true }); b.start(); await flush()
  b.metadata["web-vitals-route"] = "/news/:slug"
  const event = new Event("pageshow"); Object.defineProperty(event, "persisted", { value: true }); b.window.dispatchEvent(event)
  b.metadata["web-vitals-route"] = "/search"
  b.callbacks.LCP(b.metric("LCP", { id: "v6-1234567890124-1234567890124", navigationType: "back-forward-cache", navigationStartTime: event.timeStamp }))
  b.callbacks.LCP(b.metric())
  assert.deepEqual(b.reports.map(report => report[2].route_pattern), ["/news/:slug", "/events/:slug"])
  assert.notEqual(b.reports[0][2].metric_id, b.reports[1][2].metric_id)
})

test("malformed metrics, soft navigation and unsafe release are never forwarded", async () => {
  const b = browser({ consent: true, release: "branch/secret@example.com" }); b.start(); await flush()
  for (const extra of [{ value: NaN }, { delta: Infinity }, { name: "secret" }, { id: "user@example.com" }, { navigationType: "soft-navigation" }]) b.callbacks.LCP(b.metric("LCP", extra))
  assert.equal(b.reports.length, 0)
  b.callbacks.LCP(b.metric()); assert.equal(b.reports[0][2].release, "unknown")
})

test("failed imports and unavailable metric APIs do not reject consent events", async () => {
  const b = browser({ consent: true }); b.start(async () => { throw new Error("offline") }); await flush()
  assert.equal(b.reports.length, 0)
  const partial = browser({ consent: true }); partial.start(async () => ({})); await flush(); assert.equal(partial.reports.length, 0)
})

test("auth or backend initial documents never import or register, even with saved consent", async () => {
  const b = browser({ consent: true }); b.document.body.classList.contains = () => false
  b.start(); b.changeConsent(true); await flush(); assert.equal(b.imports, 0)
})

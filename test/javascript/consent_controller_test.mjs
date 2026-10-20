import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const consentSource = (await readFile(new URL("../../app/javascript/controllers/consent_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: ConsentController } = await import(`data:text/javascript;base64,${Buffer.from(consentSource).toString("base64")}`)
const adapterSource = await readFile(new URL("../../app/javascript/public/web_vitals.js", import.meta.url), "utf8")
const { startWebVitals } = await import(`data:text/javascript;base64,${Buffer.from(adapterSource).toString("base64")}`)

test("BFCache refresh survives Turbo controller replacement and applies saved revocation before metric callbacks", async () => {
  const window = new EventTarget(), document = new EventTarget(), reports = []
  let stored = JSON.stringify({ analytics: true, media: false })
  Object.assign(window, { localStorage: { getItem: () => stored, setItem: (_key, value) => { stored = value } },
    location: { pathname: "/events", search: "", href: "http://localhost/events" },
    PerformanceObserver: class {}, matchMedia: () => ({ matches: false }) })
  Object.assign(document, { title: "Private title", body: { dataset: { consentMeasurementIdValue: "G-TEST" },
    classList: { contains: () => true, remove() {} }, children: [] }, head: { appendChild() {} },
    createElement: () => ({ dataset: {} }),
    querySelector: selector => selector.startsWith("meta") ? { content: selector.includes("route") ? "/events" : "unknown" } : null })
  globalThis.window = window; globalThis.document = document
  const makeController = () => Object.assign(Object.create(ConsentController.prototype), { hasMeasurementIdValue: true, measurementIdValue: "G-TEST", hasMetaPixelIdValue: false,
    hasBannerTarget: false, hasAnalyticsInputTarget: false, hasMediaInputTarget: false })
  const firstController = makeController()
  startWebVitals({ window, document, loadVitals: async () => ({ onTTFB: report => {
    window.addEventListener("pageshow", event => report({ name: "TTFB", id: "v6-1234567890123-1234567890123", value: 0, delta: 0,
      navigationType: "back-forward-cache", navigationStartTime: event.timeStamp }), true)
  } }) })
  firstController.connect()
  await new Promise(resolve => setImmediate(resolve))
  firstController.disconnect()
  const currentController = makeController()
  currentController.connect()
  window.gtag = (...args) => reports.push(args)
  stored = JSON.stringify({ analytics: false, media: false })
  const restored = new Event("pageshow"); Object.defineProperty(restored, "persisted", { value: true })
  window.dispatchEvent(restored)
  assert.equal(window.StuttgartLiveConsent.preferences.analytics, false)
  assert.equal(window["ga-disable-G-TEST"], true)
  assert.equal(reports.filter(args => args[1] === "web_vital").length, 0)
  assert.equal(stored, '{"analytics":false,"media":false}')
  assert.equal(currentController.preferences.analytics, false)
  assert.equal(firstController.preferences.analytics, true)
  assert.equal(reports.filter(args => args[0] === "consent" && args[1] === "update").length, 1)
  // Existing in-memory consent survives unavailable storage on restoration.
  currentController.applyConsent({ analytics: true, media: false }, { persist: false, announce: true })
  window.localStorage.getItem = () => { throw new Error("storage unavailable") }
  currentController.refreshConsent()
  assert.equal(window.StuttgartLiveConsent.preferences.analytics, true)
  window.localStorage.getItem = () => "invalid-json"
  currentController.refreshConsent()
  assert.equal(window.StuttgartLiveConsent.preferences.analytics, false)
  currentController.disconnect()
})

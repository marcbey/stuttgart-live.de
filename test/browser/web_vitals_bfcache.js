// Same headed CLI session/config as web_vitals.js; --disable-back-forward-cache must be ignored.
async () => {
  const errors = [], failures = []
  page.on("pageerror", error => errors.push(error.message))
  page.on("requestfailed", request => failures.push({ url: request.url(), error: request.failure()?.errorText }))
  page.on("response", response => { if (response.status() >= 400) failures.push({ url: response.url(), status: response.status() }) })
  await page.bringToFront()
  await page.setViewportSize({ width: 1360, height: 900 })
  await page.context().unrouteAll()
  await page.context().route("https://www.googletagmanager.com/**", route => route.fulfill({ contentType: "application/javascript", body: "" }))
  await page.context().route("https://connect.facebook.net/**", route => route.fulfill({ contentType: "application/javascript", body: "" }))
  await page.evaluate(() => localStorage.removeItem("stuttgart-live-consent-v1"))
  await page.goto("http://localhost:3000/events")
  await page.waitForLoadState("networkidle")
  const check = (condition, message) => { if (!condition) throw new Error(message) }
  await page.evaluate(() => {
    window.task7Document = "bfcache-original"
    window.task7Pageshows = []
    addEventListener("pageshow", event => window.task7Pageshows.push({ persisted: event.persisted, path: location.pathname, time: event.timeStamp }))
    document.body.dataset.consentMeasurementIdValue = "G-TASK7"
  })
  await page.locator('.consent-banner button[data-action="click->consent#acceptAll"]').click()
  await page.waitForFunction(() => (window.dataLayer || []).some(args => args[1] === "web_vital"))
  await page.evaluate(() => window.Turbo.visit("/news"))
  await page.waitForFunction(() => location.pathname === "/news")
  await page.waitForTimeout(300)
  await page.waitForFunction(() => document.querySelector('meta[name="web-vitals-route"]').content === "/news")
  await page.evaluate(() => { document.body.dataset.consentMeasurementIdValue = "G-TASK7" })
  // No request interception during the actual restore flow.
  await page.context().unrouteAll()
  await page.goto("http://localhost:3000/session/new")
  await page.goBack({ waitUntil: "commit" })
  await page.waitForFunction(() => location.pathname === "/news")
  await page.waitForTimeout(500)
  const restored = await page.evaluate(() => ({ marker: window.task7Document, pageshows: window.task7Pageshows,
    metrics: (window.dataLayer || []).filter(args => args[1] === "web_vital").map(args => args[2]) }))
  check(restored.marker === "bfcache-original" && restored.pageshows.some(event => event.persisted), `no actual BFCache restore: ${JSON.stringify(restored)}`)
  check(restored.metrics.some(metric => metric.navigation_type === "back-forward-cache" && metric.route_pattern === "/news"), "restoration context missing")
  await page.evaluate(() => window.Turbo.visit("/search?q=task7"))
  await page.waitForFunction(() => location.pathname === "/search" && location.search === "?q=task7")
  await page.waitForFunction(() => document.querySelector('meta[name="web-vitals-route"]').content === "/search")
  await page.evaluate(() => {
    document.body.dataset.consentMeasurementIdValue = "G-TASK7"
    const button = document.createElement("button"); button.id = "task7-bfcache-interaction"; button.textContent = "BFCache interaction"
    button.style.cssText = "position:fixed;top:100px;left:5px;z-index:99999"
    button.onclick = () => { const start = performance.now(); while (performance.now() - start < 80) {} }
    document.body.append(button)
  })
  await page.locator("#task7-bfcache-interaction").click()
  await page.waitForTimeout(250)
  const result = await page.evaluate(() => ({ pageshows: window.task7Pageshows,
    metrics: (window.dataLayer || []).filter(args => args[1] === "web_vital").map(args => args[2]) }))
  const hard = result.metrics.filter(metric => metric.navigation_type !== "back-forward-cache")
  const cache = result.metrics.filter(metric => metric.navigation_type === "back-forward-cache")
  check(cache.some(metric => metric.metric_name === "INP"), "restored INP missing after later Turbo")
  check(hard.every(metric => metric.route_pattern === "/events") && cache.every(metric => metric.route_pattern === "/news"), "delayed context drifted")
  check(cache.every(metric => !hard.some(original => original.metric_id === metric.metric_id)), "restoration reused metric IDs")
  // A is cached with consent granted; B revokes it in the real settings UI.
  await page.evaluate(() => addEventListener("pagehide", () => {
    window.task7BeforeExternalRevoke = (window.dataLayer || []).filter(args => args[1] === "web_vital").length
  }, { once: true }))
  await page.goto("http://localhost:3000/news?task7=other-document")
  await page.getByRole("button", { name: "Menü öffnen", exact: true }).click()
  await page.locator(".design-preview-menu-privacy-button").click()
  await page.locator("#consent-analytics").uncheck()
  await page.locator('button[data-action="click->consent#savePreferences"]').click()
  await page.waitForFunction(() => window.StuttgartLiveConsent.preferences.analytics === false)
  await page.goBack({ waitUntil: "commit" })
  await page.waitForFunction(() => window.task7Document === "bfcache-original")
  await page.waitForTimeout(300)
  const revoked = await page.evaluate(() => ({ pageshows: window.task7Pageshows,
    consent: window.StuttgartLiveConsent.preferences.analytics, disabled: window["ga-disable-G-TASK7"],
    before: window.task7BeforeExternalRevoke, after: (window.dataLayer || []).filter(args => args[1] === "web_vital").length }))
  check(new Set(revoked.pageshows.filter(event => event.persisted).map(event => event.time)).size >= 2, "revocation boundary did not use BFCache")
  check(revoked.consent === false && revoked.disabled === true && revoked.before === revoked.after, `stale consent reported on restore: ${JSON.stringify(revoked)}`)
  check(errors.length === 0 && failures.length === 0, `BFCache errors/resources: ${JSON.stringify({ errors, failures })}`)
  return { result: "PASS", ...result, revoked, errors, failures }

}

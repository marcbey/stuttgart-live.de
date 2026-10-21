// First navigate the CLI to a locally generated valid password-reset URL.
// No password is submitted or changed by this check.
async () => {
  const errors = []
  page.on("pageerror", error => errors.push(error.message))
  const check = (condition, message) => { if (!condition) throw new Error(message) }
  check(await page.locator('script[src*="/backend"]').count() === 1 && await page.locator('script[src*="/public"]').count() === 0, "reset assets incorrect")
  check(await page.locator('link[rel=stylesheet][href*="/backend"]').count() === 1, "reset CSS incorrect")
  check(await page.locator('body.page-auth-backoffice').count() === 1, "reset auth chrome missing")
  check(await page.locator('meta[name="web-vitals-route"], .consent-banner, [data-controller~=consent]').count() === 0, "reset includes public metrics/consent")
  check(await page.locator('input[type="password"]').count() === 2, "reset confirmation form missing")
  check(await page.locator('form input[name="_method"]').getAttribute('value') === "put", "reset submission method changed")
  await page.setViewportSize({ width: 390, height: 844 })
  const nav = page.locator('.app-nav-toggle')
  await nav.click(); check(await nav.getAttribute('aria-expanded') === "true", "reset mobile navigation failed")
  check(errors.length === 0, `reset JS errors: ${errors}`)
  return { result: "PASS", auth: "valid reset form, backend CSS/JS, mobile navigation, no public metrics or consent", errors }
}

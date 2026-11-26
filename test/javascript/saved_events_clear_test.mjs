import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const dataUrl = source => `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const storageUrl = dataUrl(await readFile(new URL("../../app/javascript/lib/saved_events_storage.js", import.meta.url), "utf8"))
async function loadController(name) {
  const source = (await readFile(new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url), "utf8"))
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace('import { Turbo } from "@hotwired/turbo-rails"', "const Turbo = { visit: (...args) => window.testTurboVisit(...args) }")
    .replace('"../lib/saved_events_storage"', JSON.stringify(storageUrl))
  return (await import(dataUrl(`${source}\n//# sourceURL=${name}_controller.js`))).default
}
const ClearController = await loadController("saved_events_clear")
const LaneController = await loadController("saved_events_lane")
const storageKey = "stuttgart-live:saved-events"

function browserFor(t, href = "https://stuttgart-live.de/deine-events") {
  const values = new Map([[storageKey, JSON.stringify(["one", "two"])], ["unrelated", "keep"]])
  const browser = Object.assign(new EventTarget(), {
    navigations: [],
    localStorage: {
      getItem: key => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, value),
      removeItem: key => values.delete(key)
    },
    location: new URL(href),
    confirm: () => true,
    alert: () => {},
    testTurboVisit(url, options) {
      browser.navigations.push({ url, options })
      browser.location = new URL(url)
    },
    history: {
      state: { turbo: "preserve" },
      replaceState(state, _title, url) { browser.location = new URL(url); this.state = state }
    }
  })
  const original = globalThis.window
  globalThis.window = browser
  const controller = Object.assign(new ClearController(), {
    element: { hidden: true }, pageUrlValue: "/deine-events"
  })
  controller.connect()
  t.after(() => {
    controller.disconnect()
    globalThis.window = original
  })
  return { browser, values, controller }
}
const click = { preventDefault() {}, stopPropagation() {} }

test("canceling leaves the saved list and shared URL intact", t => {
  const { browser, values, controller } = browserFor(t, "https://stuttgart-live.de/deine-events?slugs[]=one")
  browser.confirm = () => false
  let changes = 0
  browser.addEventListener("saved-events:changed", () => changes++)

  controller.clear(click)

  assert.deepEqual(JSON.parse(values.get(storageKey)), ["one", "two"])
  assert.equal(browser.location.searchParams.get("slugs[]"), "one")
  assert.equal(changes, 0)
})

test("confirming clears only favorites and notifies all saved-event controls", t => {
  const { browser, values, controller } = browserFor(t)
  let detail
  browser.addEventListener("saved-events:changed", event => { detail = event.detail })
  assert.equal(controller.element.hidden, false)

  controller.clear(click)

  assert.deepEqual(JSON.parse(values.get(storageKey)), [])
  assert.equal(values.get("unrelated"), "keep")
  assert.equal(detail.cleared, true)
  assert.equal(controller.element.hidden, true)
})

test("clearing a shared overview replaces the URL through Turbo so back navigation remains tracked", t => {
  const { browser, values, controller } = browserFor(t, "https://stuttgart-live.de/deine-events?slugs[]=one&slugs[]=two&filter=all#events")
  values.set(storageKey, "[]")
  controller.render()
  assert.equal(controller.element.hidden, false)

  controller.clear(click)

  assert.equal(browser.location.href, "https://stuttgart-live.de/deine-events?filter=all#events")
  assert.deepEqual(browser.history.state, { turbo: "preserve" })
  assert.deepEqual(browser.navigations, [{ url: "https://stuttgart-live.de/deine-events?filter=all#events", options: { action: "replace" } }])
  assert.equal(controller.element.hidden, true)
})

test("storage failures preserve the list and shared selection and report an error", t => {
  const { browser, values, controller } = browserFor(t, "https://stuttgart-live.de/deine-events?slugs[]=one")
  browser.localStorage.setItem = () => { throw new Error("Storage blocked") }
  let message
  browser.alert = text => { message = text }

  controller.clear(click)

  assert.deepEqual(JSON.parse(values.get(storageKey)), ["one", "two"])
  assert.equal(browser.location.searchParams.get("slugs[]"), "one")
  assert.match(message, /nicht geleert/)
})

test("clear buttons disappear and return when another tab changes the saved list", t => {
  const { browser, values, controller } = browserFor(t)
  values.set(storageKey, "[]")
  browser.dispatchEvent(new Event("storage"))
  assert.equal(controller.element.hidden, true)
  values.set(storageKey, '["new-event"]')
  browser.dispatchEvent(new Event("storage"))
  assert.equal(controller.element.hidden, false)
})

test("a response already loading cannot restore a lane after the list is cleared", async t => {
  const { values } = browserFor(t)
  let finishBody
  const body = new Promise(resolve => { finishBody = resolve })
  t.mock.method(globalThis, "fetch", async () => ({ ok: true, text: () => body }))
  const controller = Object.assign(new LaneController(), {
    requestId: 0, hasUrlValue: true, urlValue: "/events/saved_lane", showEmptyValue: false, shareButtonTargets: [],
    element: { innerHTML: "Old events", hidden: false }
  })
  const pending = controller.load()
  await Promise.resolve()
  values.set(storageKey, "[]")
  await controller.load()
  finishBody("Stale events")
  await pending

  assert.equal(controller.element.innerHTML, "")
  assert.equal(controller.element.hidden, true)
})


test("changing a selection disables stale sharing immediately, including after a failed refresh", async t => {
  const { values } = browserFor(t)
  let finishResponse
  const response = new Promise(resolve => { finishResponse = resolve })
  t.mock.method(globalThis, "fetch", () => response)
  t.mock.method(console, "error", () => {})
  const buttons = [{ disabled: false }, { disabled: false }]
  const controller = Object.assign(new LaneController(), {
    requestId: 0, hasUrlValue: true, urlValue: "/events/saved_lane", showEmptyValue: false,
    shareButtonTargets: buttons, element: { innerHTML: "Previous selection", hidden: false }
  })
  values.set(storageKey, '["two"]')

  const pending = controller.load()
  assert.ok(buttons.every(button => button.disabled))
  finishResponse({ ok: false, status: 503, text: async () => "Unavailable" })
  await pending

  assert.ok(buttons.every(button => button.disabled))
  assert.equal(controller.element.innerHTML, "Previous selection")
})

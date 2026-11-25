import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/design_preview_saved_dropdown_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace('import { STORAGE_KEY, removeSavedEvent, savedEventSlugs } from "../lib/saved_events_storage"', 'const savedEventSlugs = () => window.testSavedSlugs || []')
const { default: SavedDropdownController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

globalThis.window = { location: { origin: "https://stuttgart-live.de" } }
function useNavigator(t, value) {
  const original = Object.getOwnPropertyDescriptor(globalThis, "navigator")
  Object.defineProperty(globalThis, "navigator", { configurable: true, value })
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "navigator", original)
    else delete globalThis.navigator
  })
}

const item = (slug, shareText, hidden = false) => ({ hidden, dataset: { slug, shareText } })
const controllerFor = items => {
  window.testSavedSlugs = items.filter(item => !item.hidden).map(item => item.dataset.slug)
  return Object.assign(new SavedDropdownController(), {
    loadedKey: window.testSavedSlugs.join("\n"),
  itemTargets: items,
  hasShareUrlValue: true,
  shareUrlValue: "/deine-events",
  hasShareStatusTarget: false
  })
}

test("native sharing includes selected event information and excludes removed events", async t => {
  let shared
  useNavigator(t, { share: async data => { shared = data } })
  const controller = controllerFor([
    item("paulk", "Paulk\nDatum: 05.12.2026\nOrt: Im Wizemann"),
    item("removed", "Removed Artist", true),
    item("nino", "Nino\nDatum: 06.12.2026\nOrt: LKA Longhorn")
  ])

  await controller.share({ preventDefault() {} })

  assert.equal(shared.title, "Meine Merkliste bei STUTTGART LIVE")
  assert.equal(shared.text, "Meine Eventauswahl bei STUTTGART LIVE\n2 Events\n\n1. Paulk\nDatum: 05.12.2026\nOrt: Im Wizemann\n\n2. Nino\nDatum: 06.12.2026\nOrt: LKA Longhorn\n\nDie gesamte Auswahl mit Bildern und weiteren Infos:")
  assert.deepEqual(new URL(shared.url).searchParams.getAll("slugs[]"), ["paulk", "nino"])
})

test("all twenty events appear as separate numbered blocks without truncation", async t => {
  let shared
  useNavigator(t, { share: async data => { shared = data } })
  const controller = controllerFor(Array.from({ length: 20 }, (_, i) => item(`event-${i + 1}`, `Artist ${i + 1}\nDatum: ${String(i + 1).padStart(2, "0")}.12.2026\nOrt: Testclub`)))

  await controller.share({ preventDefault() {} })

  assert.match(shared.text, /\n20 Events\n/)
  assert.equal(shared.text.match(/^\d+\. Artist /gm).length, 20)
  assert.match(shared.text, /\n\n6\. Artist 6\nDatum: 06\.12\.2026\nOrt: Testclub\n\n/)
  assert.match(shared.text, /\n\n20\. Artist 20\nDatum: 20\.12\.2026\nOrt: Testclub\n\n/)
  assert.doesNotMatch(shared.text, /weitere Events|…/)
  assert.equal(new URL(shared.url).searchParams.getAll("slugs[]").length, 20)
})

test("copy link fallback keeps a directly usable selection url", async t => {
  let copied
  useNavigator(t, { clipboard: { writeText: async text => { copied = text } } })
  const controller = controllerFor([item("paulk", "Paulk · 05.12.2026 · Im Wizemann")])

  await controller.share({ preventDefault() {} })

  assert.deepEqual(new URL(copied).searchParams.getAll("slugs[]"), ["paulk"])
})

test("a single event gets a singular count and retains punctuation in its name", async t => {
  let shared
  useNavigator(t, { share: async data => { shared = data } })
  const controller = controllerFor([item("act", "Act · Friends\nDatum: 05.12.2026\nOrt: Testclub")])

  await controller.share({ preventDefault() {} })

  assert.match(shared.text, /\n1 Event\n\n1\. Act · Friends\nDatum: 05\.12\.2026\nOrt: Testclub\n\n/)
})

test("sharing cannot use an empty or stale list while the selection is loading", async t => {
  let operations = 0
  useNavigator(t, {
    share: async () => { operations += 1 },
    clipboard: { writeText: async () => { operations += 1 } }
  })
  const controller = controllerFor([item("current", "Current Event")])
  controller.loadedKey = undefined
  await controller.share({ preventDefault() {} })
  controller.loadedKey = "old-event"
  await controller.share({ preventDefault() {} })
  assert.equal(operations, 0)
})

test("render disables sharing while loading and enables it for the loaded selection", () => {
  const controller = controllerFor([item("current", "Current Event")])
  Object.assign(controller, {
    element: { classList: { toggle() {} } },
    buttonTarget: { setAttribute() {} },
    shareButtonTargets: [{ disabled: false }]
  })
  controller.loadedKey = undefined
  controller.render()
  assert.ok(controller.shareButtonTargets.every(button => button.disabled))
  controller.loadedKey = "current"
  controller.render()
  assert.ok(controller.shareButtonTargets.every(button => !button.disabled))
})

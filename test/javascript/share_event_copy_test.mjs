import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/share_event_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: ShareEventController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

const event = { preventDefault() {}, stopPropagation() {} }

test("explicit copy uses the selection URL even when native sharing is available", async t => {
  let copied
  let status
  let shares = 0
  const original = Object.getOwnPropertyDescriptor(globalThis, "navigator")
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: {
    share: async () => { shares += 1 },
    clipboard: { writeText: async text => { copied = text } }
  } })
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "navigator", original)
    else delete globalThis.navigator
  })
  const controller = Object.assign(new ShareEventController(), {
    hasUrlValue: true,
    urlValue: "https://stuttgart-live.de/deine-events?slugs%5B%5D=act",
    copiedLabelValue: "Link kopiert",
    showStatus: message => { status = message }
  })

  await controller.copyLink(event)

  assert.equal(shares, 0)
  assert.equal(copied, controller.urlValue)
  assert.equal(status, "Link kopiert")
})

test("copy errors show feedback without reporting success", async () => {
  let status
  const controller = Object.assign(new ShareEventController(), {
    copyUrl: async () => { throw new Error("Clipboard denied") },
    errorLabelValue: "Link konnte nicht kopiert werden",
    showStatus: message => { status = message }
  })

  await controller.copyLink(event)

  assert.equal(status, "Link konnte nicht kopiert werden")
})

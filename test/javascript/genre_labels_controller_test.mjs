import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/genre_labels_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: GenreLabelsController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

const label = genreName => ({ dataset: { genreName } })
const collection = names => Object.assign(new GenreLabelsController(), {
  element: { isConnected: true, dataset: {} },
  labelTargets: names.map(label)
})
const flush = () => new Promise(resolve => queueMicrotask(resolve))

test("each collection independently hides repeated genres and shows mixed genres", async () => {
  const same = collection(["Pop", "Pop"])
  const mixed = collection(["Pop", "Rock"])
  same.connect()
  mixed.connect()
  await flush()
  assert.equal(same.element.dataset.genresMixed, "false")
  assert.equal(mixed.element.dataset.genresMixed, "true")
})

test("pagination reveals all labels when a second genre arrives and removal restores hiding", async () => {
  const controller = collection(["Pop", "Pop"])
  controller.connect()
  await flush()
  controller.labelTargets.push(label("Pop"))
  controller.labelTargetConnected()
  await flush()
  assert.equal(controller.element.dataset.genresMixed, "false")
  controller.labelTargets.push(label("Rock"))
  controller.labelTargetConnected()
  await flush()
  assert.equal(controller.element.dataset.genresMixed, "true")
  controller.labelTargets.pop()
  controller.labelTargetDisconnected()
  await flush()
  assert.equal(controller.element.dataset.genresMixed, "false")
})

test("empty, single-event and unclassified collections do not show redundant labels", async () => {
  for (const names of [[], ["Pop"], ["", "Pop"], ["", ""]]) {
    const controller = collection(names)
    controller.connect()
    await flush()
    assert.equal(controller.element.dataset.genresMixed, "false")
  }
})

test("a pending update does not touch a removed collection", async () => {
  const controller = collection(["Pop", "Rock"])
  controller.connect()
  controller.element.isConnected = false
  await flush()
  assert.equal(controller.element.dataset.genresMixed, undefined)
})

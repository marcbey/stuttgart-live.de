import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/public_search_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: SearchController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

function calendar(mode, intercepted = true) {
  const events = []
  let submissions = 0
  const controller = Object.assign(new SearchController(), {
    calendarPanelTarget: { dataset: { calendarSelectionMode: mode } },
    inputTarget: { value: "" },
    element: { requestSubmit: () => submissions++ },
    dispatch: (name, options) => {
      events.push({ name, detail: options?.detail })
      return { defaultPrevented: intercepted }
    },
    renderCalendar() {}, closeCalendar() {}, closeSearchPanel() {},
    syncControls() {}, syncPlaceholderAnimation() {}
  })
  return {
    controller, events, submissions: () => submissions,
    select: date => controller.selectCalendarDate({ preventDefault() {}, currentTarget: { dataset: { date } } })
  }
}

test("filter calendar selects a single day immediately without submitting the search form", () => {
  const picker = calendar("day")
  picker.select("2030-07-30")
  assert.deepEqual(picker.events, [{ name: "calendar-selected", detail: { start: "2030-07-30", end: "2030-07-30" } }])
  assert.equal(picker.submissions(), 0)
  assert.equal(picker.controller.inputTarget.value, "")
})

test("range selection waits for the second click and sorts reversed dates across months", () => {
  const picker = calendar("range")
  picker.select("2030-08-02")
  assert.deepEqual(picker.events, [])
  picker.select("2030-07-30")
  assert.deepEqual(picker.events[0].detail, { start: "2030-07-30", end: "2030-08-02" })
  assert.equal(picker.submissions(), 0)
})

test("the normal header calendar still submits its date range to search", () => {
  const picker = calendar(undefined, false)
  picker.select("2030-07-30")
  picker.select("2030-08-02")
  assert.equal(picker.controller.inputTarget.value, "von 30.7.2030 bis 2.8.2030")
  assert.equal(picker.submissions(), 1)
})

test("switching calendar modes clears an unfinished range", () => {
  const picker = calendar("range")
  picker.select("2030-07-30")
  picker.controller.resetCalendarSelection()
  picker.select("2030-08-02")
  assert.deepEqual(picker.events, [])
  picker.select("2030-08-02")
  assert.deepEqual(picker.events[0].detail, { start: "2030-08-02", end: "2030-08-02" })
})

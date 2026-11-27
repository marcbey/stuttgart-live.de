import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const source = (await readFile(new URL("../../app/javascript/controllers/newsletter_team_tip_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: NewsletterTeamTipController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

test("selecting an author immediately replaces the heading", () => {
  const controller = Object.assign(new NewsletterTeamTipController(), {
    profileTarget: { selectedOptions: [{ dataset: { tipTitle: "Kathis Wochentipp" } }] },
    titleTarget: { value: "Sarahs Wochentipp" }
  })

  controller.updateTitle()
  assert.equal(controller.titleTarget.value, "Kathis Wochentipp")

  controller.titleTarget.value = "Mein besonderer Tipp"
  controller.profileTarget.selectedOptions = [{ dataset: { tipTitle: "Michis Wochentipp" } }]
  controller.updateTitle()
  assert.equal(controller.titleTarget.value, "Michis Wochentipp")
})

test("selecting no personal tip clears the heading", () => {
  const controller = Object.assign(new NewsletterTeamTipController(), {
    profileTarget: { selectedOptions: [{ dataset: {} }] },
    titleTarget: { value: "Kathis Wochentipp" }
  })

  controller.updateTitle()

  assert.equal(controller.titleTarget.value, "")
})

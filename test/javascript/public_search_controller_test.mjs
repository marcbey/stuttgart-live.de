import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { createServer } from "node:http"

const source = (await readFile(new URL("../../app/javascript/controllers/public_search_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
const { default: SearchController } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

globalThis.document = { body: {} }
let requests = []
let failNext = false
const server = createServer((request, response) => {
  requests.push(request.url)
  const fail = failNext
  failNext = false
  setTimeout(() => {
    response.writeHead(fail ? 503 : 200)
    response.end(fail ? "unavailable" : `<a>${request.url}</a>`)
  }, 35)
})
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
const origin = `http://127.0.0.1:${server.address().port}`

function toolbar(date = "", query = "") {
  const controller = Object.create(SearchController.prototype)
  Object.assign(controller, {
    resultsTarget: { innerHTML: "" }, idleTemplateTarget: { innerHTML: "HEUTE" },
    element: { isConnected: true }, inputTarget: { value: query }, abortController: null, lastRequestKey: null,
    buildRequestUrl: () => `${origin}/events/search_overlay?event_date=${date}&q=${controller.inputTarget.value}`,
    buildRequestKey: () => controller.buildRequestUrl()
  })
  return controller
}

try {
  await test("first focus and repeated open share one idle request across two toolbars", async () => {
    requests = []
    document.body = {}
    const first = toolbar()
    const second = toolbar()
    first.loadIdleResults()
    first.loadIdleResults()
    second.loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 180))
    assert.equal(requests.length, 1)
    assert.match(first.resultsTarget.innerHTML, /search_overlay/)
    assert.equal(first.resultsTarget.innerHTML, second.resultsTarget.innerHTML)
    second.loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 70))
    assert.equal(requests.length, 1)
  })
  await test("idle failures retry and date and Turbo body changes request fresh suggestions", async () => {
    requests = []
    document.body = {}
    failNext = true
    const first = toolbar("2026-10-22")
    first.loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 80))
    first.loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 80))
    assert.match(first.resultsTarget.innerHTML, /2026-10-22/)
    toolbar("2026-10-23").loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 80))
    document.body = {}
    toolbar("2026-10-22").loadIdleResults()
    await new Promise(resolve => setTimeout(resolve, 80))
    assert.equal(requests.length, 4)
  })
  await test("typing during idle loading never replaces current query results with idle suggestions", async () => {
    document.body = {}
    const controller = toolbar()
    controller.loadIdleResults()
    controller.inputTarget.value = "rock"
    await controller.fetchResults()
    await new Promise(resolve => setTimeout(resolve, 80))
    assert.match(controller.resultsTarget.innerHTML, /q=rock/)
  })
} finally {
  server.close()
}

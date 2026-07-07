import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "grid", "list", "pagination", "status"]
  static values = {
    cursor: String,
    lane: String,
    listCursor: String,
    perPage: { type: Number, default: 20 },
    url: String
  }

  connect() {
    this.loading = false
    if (!this.hasListCursorValue && this.hasCursorValue) this.listCursorValue = this.cursorValue
    this.updateAvailability()
  }

  async load(event) {
    event?.preventDefault()
    if (this.loading || !this.canLoad) return

    this.loading = true
    this.setPending(true)
    this.updateStatus("Weitere Events werden geladen ...")

    try {
      const [cardPage, rowPage] = await Promise.all([
        this.fetchPage("cards", this.cursorValue),
        this.fetchPage("rows", this.listCursorValue)
      ])

      this.appendHtml(this.gridTarget, cardPage.html)
      this.appendHtml(this.listTarget, rowPage.html)
      this.cursorValue = cardPage.nextCursor
      this.listCursorValue = rowPage.nextCursor
      this.updateStatus(cardPage.html.trim().length > 0 ? "Weitere Events wurden geladen." : "")
    } catch (_error) {
      this.updateStatus("Weitere Events konnten nicht geladen werden.")
    } finally {
      this.loading = false
      this.setPending(false)
      this.updateAvailability()
    }
  }

  async fetchPage(mode, cursor) {
    const response = await fetch(this.requestUrl(mode, cursor), {
      headers: {
        Accept: "text/html",
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })

    if (!response.ok) throw new Error(`Lane page request failed (${response.status})`)

    return {
      html: await response.text(),
      nextCursor: response.headers.get("X-Homepage-Lane-Next-Cursor") || ""
    }
  }

  requestUrl(mode, cursor) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("lane", this.laneValue)
    url.searchParams.set("cursor", cursor || "")
    url.searchParams.set("mode", mode)
    url.searchParams.set("per_page", this.perPageValue.toString())
    return url.toString()
  }

  appendHtml(target, html) {
    if (!target || html.trim().length === 0) return

    const template = document.createElement("template")
    template.innerHTML = html.trim()
    target.append(...Array.from(template.content.children))
  }

  updateAvailability() {
    if (!this.hasPaginationTarget) return

    this.paginationTarget.hidden = !this.canLoad
  }

  setPending(pending) {
    if (!this.hasButtonTarget) return

    this.buttonTarget.disabled = pending
    this.buttonTarget.classList.toggle("is-loading", pending)
  }

  updateStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }

  get canLoad() {
    if (!this.hasUrlValue || !this.hasLaneValue) return false

    return this.cursorValue.length > 0 || this.listCursorValue.length > 0
  }
}

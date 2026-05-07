import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "track", "link", "list" ]
  static values = {
    cursor: String,
    lane: String,
    listCursor: String,
    listLimit: { type: Number, default: 12 },
    maxPagesDesktop: { type: Number, default: 3 },
    maxPagesMobile: { type: Number, default: 2 },
    perPage: { type: Number, default: 10 },
    url: String
  }

  connect() {
    this.loading = false
    this.pageIndex = 0
    this.pages = []
    this.storedPages = new Map()
    this.listPageIndex = 0
    this.listPages = []
    this.storedListPages = new Map()
    this.raf = null
    this.listRaf = null
    this.abortController = null
    this.listAbortController = null
    this.initialCursor = this.cursorValue || ""
    this.listLoading = false
    this.userInteracted = false
    this.handleScroll = this.handleScroll.bind(this)
    this.handleListScroll = this.handleListScroll.bind(this)
    this.markUserInteraction = this.markUserInteraction.bind(this)
    this.handleLoadRequest = this.handleLoadRequest.bind(this)
    this.handleListShown = this.handleListShown.bind(this)
    this.element.addEventListener("homepage-lane:load", this.handleLoadRequest)
    this.element.addEventListener("section-view:list-shown", this.handleListShown)

    if (this.hasTrackTarget) {
      this.trackTarget.addEventListener("scroll", this.handleScroll, { passive: true })
      this.trackTarget.addEventListener("keydown", this.markUserInteraction)
      this.trackTarget.addEventListener("pointerdown", this.markUserInteraction, { passive: true })
      this.trackTarget.addEventListener("touchstart", this.markUserInteraction, { passive: true })
      this.trackTarget.addEventListener("wheel", this.markUserInteraction, { passive: true })
      this.registerInitialPage()
    }

    if (this.hasListTarget) {
      this.listTarget.addEventListener("scroll", this.handleListScroll, { passive: true })
      this.listTarget.addEventListener("keydown", this.markUserInteraction)
      this.listTarget.addEventListener("pointerdown", this.markUserInteraction, { passive: true })
      this.listTarget.addEventListener("touchstart", this.markUserInteraction, { passive: true })
      this.listTarget.addEventListener("wheel", this.markUserInteraction, { passive: true })
      this.registerInitialListPage()
    }

    if (!this.hasListCursorValue && this.initialCursor.length > 0) this.listCursorValue = this.initialCursor
    this.updateLink()
  }

  disconnect() {
    if (this.hasTrackTarget) {
      this.trackTarget.removeEventListener("scroll", this.handleScroll)
      this.trackTarget.removeEventListener("keydown", this.markUserInteraction)
      this.trackTarget.removeEventListener("pointerdown", this.markUserInteraction)
      this.trackTarget.removeEventListener("touchstart", this.markUserInteraction)
      this.trackTarget.removeEventListener("wheel", this.markUserInteraction)
    }

    if (this.hasListTarget) {
      this.listTarget.removeEventListener("scroll", this.handleListScroll)
      this.listTarget.removeEventListener("keydown", this.markUserInteraction)
      this.listTarget.removeEventListener("pointerdown", this.markUserInteraction)
      this.listTarget.removeEventListener("touchstart", this.markUserInteraction)
      this.listTarget.removeEventListener("wheel", this.markUserInteraction)
    }

    this.element.removeEventListener("homepage-lane:load", this.handleLoadRequest)
    this.element.removeEventListener("section-view:list-shown", this.handleListShown)
    if (this.raf) window.cancelAnimationFrame(this.raf)
    if (this.listRaf) window.cancelAnimationFrame(this.listRaf)
    this.abortPendingRequest()
    this.abortPendingListRequest()
  }

  async load(event) {
    event?.preventDefault()
    if (this.loading || !this.canLoad) return

    const advanceAfterLoad = event?.detail?.advance === true
    this.loading = true
    this.setPending(true)
    this.abortPendingRequest()

    const abortController = new AbortController()
    this.abortController = abortController

    try {
      const response = await fetch(this.requestUrl("cards"), {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: abortController.signal
      })

      if (!response.ok) throw new Error(`Homepage lane request failed (${response.status})`)

      const html = await response.text()
      const nextCursor = response.headers.get("X-Homepage-Lane-Next-Cursor") || ""
      let appendedElements = []

      if (html.trim().length > 0) {
        appendedElements = this.appendPage(html)
      }

      this.cursorValue = nextCursor
      this.updateLink()
      this.scheduleTrackWork()
      if (advanceAfterLoad) this.scrollToAppendedPage(appendedElements)
    } catch (error) {
      if (error.name !== "AbortError") console.error(error)
    } finally {
      if (this.abortController === abortController) this.abortController = null
      this.loading = false
      this.setPending(false)
    }
  }

  handleScroll() {
    if (!this.userInteracted) return

    this.scheduleTrackWork()
  }

  handleListScroll() {
    if (!this.userInteracted) return

    this.scheduleListWork()
  }

  markUserInteraction() {
    this.userInteracted = true
  }

  handleLoadRequest(event) {
    if (!this.canLoad) return

    this.markUserInteraction()
    event.preventDefault()
    this.load(event)
  }

  previousList(event) {
    event.preventDefault()
    this.scrollListByPage(-1)
  }

  nextList(event) {
    event.preventDefault()
    this.scrollListByPage(1)
  }

  handleListShown() {
    this.ensureListLimit()
    this.scheduleListWork()
  }

  async ensureListLimit() {
    if (this.listLoading || !this.hasListTarget) return

    const missingRows = this.listLimitValue - this.listRowCount
    if (missingRows <= 0) return

    await this.loadListRows({ perPage: missingRows, appendToInitialPage: true })
  }

  async loadListRows({ perPage = this.listLimitValue, appendToInitialPage = false } = {}) {
    if (this.listLoading || !this.canLoadListRows) return

    this.listLoading = true
    this.abortPendingListRequest()

    const abortController = new AbortController()
    this.listAbortController = abortController

    try {
      const response = await fetch(this.requestUrl("rows", { cursor: this.listCursorValue, perPage: perPage }), {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: abortController.signal
      })

      if (!response.ok) throw new Error(`Homepage lane row request failed (${response.status})`)

      const html = await response.text()
      const nextCursor = response.headers.get("X-Homepage-Lane-Next-Cursor") || ""
      if (html.trim().length > 0) this.appendListRows(html, { appendToInitialPage })
      this.listCursorValue = nextCursor
    } catch (error) {
      if (error.name !== "AbortError") console.error(error)
    } finally {
      if (this.listAbortController === abortController) this.listAbortController = null
      this.listLoading = false
      if (this.listVisible) this.scheduleListWork()
    }
  }

  scheduleTrackWork() {
    if (this.raf) return

    this.raf = window.requestAnimationFrame(() => {
      this.raf = null
      this.restoreNearbyPlaceholders()
      this.pruneDistantPages()
      if (this.nearEnd()) this.load()
    })
  }

  scheduleListWork() {
    if (this.listRaf) return

    this.listRaf = window.requestAnimationFrame(() => {
      this.listRaf = null
      this.restoreNearbyListPlaceholders()
      this.pruneDistantListPages()
      if (this.listNearEnd()) this.loadListRows()
    })
  }

  appendPage(html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const elements = Array.from(template.content.children).filter((element) => element instanceof HTMLElement)
    if (elements.length === 0) return []

    const index = ++this.pageIndex
    elements.forEach((element) => {
      element.dataset.homepageLanePage = index.toString()
      this.trackTarget.appendChild(element)
    })
    this.pages.push({ index, elements })
    return elements
  }

  scrollToAppendedPage(elements) {
    const firstElement = elements.find((element) => element instanceof HTMLElement)
    if (!firstElement) return

    window.requestAnimationFrame(() => {
      this.trackTarget.scrollTo({ left: firstElement.offsetLeft, behavior: "smooth" })
    })
  }

  registerInitialPage() {
    const elements = Array.from(this.trackTarget.children).filter((element) => element instanceof HTMLElement)
    elements.forEach((element) => {
      element.dataset.homepageLanePage = "0"
    })
    this.pages = [{ index: 0, elements }]
  }

  registerInitialListPage() {
    const elements = Array.from(this.listContainer.children).filter((element) => element instanceof HTMLElement)
    elements.forEach((element) => {
      element.dataset.homepageLaneListPage = "0"
    })
    this.listPages = [{ index: 0, elements }]
  }

  pruneDistantPages() {
    const activePages = this.pages.filter((page) => !this.pagePruned(page))
    const removableCount = activePages.length - this.maxRenderedPages
    if (removableCount <= 0) return

    const viewportStart = this.trackTarget.scrollLeft
    const pruneBefore = viewportStart - this.trackTarget.clientWidth
    let pruned = 0

    for (const page of activePages) {
      if (pruned >= removableCount) break
      if (this.pageEnd(page) >= pruneBefore) continue

      this.prunePage(page)
      pruned += 1
    }
  }

  prunePage(page) {
    const stored = []

    page.elements = page.elements.map((element) => {
      if (!element.isConnected || this.isPlaceholder(element)) return element

      const placeholder = document.createElement(element.tagName.toLowerCase())
      placeholder.className = `${element.className} homepage-lane-placeholder`
      placeholder.dataset.homepageLanePage = page.index.toString()
      placeholder.dataset.homepageLanePlaceholder = "true"
      placeholder.setAttribute("aria-hidden", "true")
      stored.push(element.outerHTML)
      element.replaceWith(placeholder)
      return placeholder
    })

    if (stored.length > 0) this.storedPages.set(page.index, stored)
  }

  restoreNearbyPlaceholders() {
    const viewportStart = this.trackTarget.scrollLeft - this.trackTarget.clientWidth
    const viewportEnd = this.trackTarget.scrollLeft + (this.trackTarget.clientWidth * 2)

    this.pages.forEach((page) => {
      if (!this.pagePruned(page)) return
      if (this.pageEnd(page) < viewportStart || this.pageStart(page) > viewportEnd) return

      this.restorePage(page)
    })
  }

  restorePage(page) {
    const stored = this.storedPages.get(page.index)
    if (!stored) return

    page.elements = page.elements.map((placeholder, index) => {
      if (!this.isPlaceholder(placeholder)) return placeholder

      const template = document.createElement("template")
      template.innerHTML = stored[index] || ""
      const restored = template.content.firstElementChild
      if (!(restored instanceof HTMLElement)) return placeholder

      restored.dataset.homepageLanePage = page.index.toString()
      placeholder.replaceWith(restored)
      return restored
    })

    this.storedPages.delete(page.index)
  }

  pruneDistantListPages() {
    const activePages = this.listPages.filter((page) => !this.listPagePruned(page))
    const removableCount = activePages.length - this.maxRenderedPages
    if (removableCount <= 0) return

    const viewportStart = this.listTarget.scrollLeft
    const pruneBefore = viewportStart - this.listTarget.clientWidth
    let pruned = 0

    for (const page of activePages) {
      if (pruned >= removableCount) break
      if (this.listPageEnd(page) >= pruneBefore) continue

      this.pruneListPage(page)
      pruned += 1
    }
  }

  pruneListPage(page) {
    const stored = []

    page.elements = page.elements.map((element) => {
      if (!element.isConnected || this.isListPlaceholder(element)) return element

      const placeholder = document.createElement(element.tagName.toLowerCase())
      placeholder.className = `${element.className} homepage-lane-list-placeholder`
      placeholder.dataset.homepageLaneListPage = page.index.toString()
      placeholder.dataset.homepageLaneListPlaceholder = "true"
      placeholder.setAttribute("aria-hidden", "true")
      placeholder.style.minHeight = `${element.offsetHeight}px`
      stored.push(element.outerHTML)
      element.replaceWith(placeholder)
      return placeholder
    })

    if (stored.length > 0) this.storedListPages.set(page.index, stored)
  }

  restoreNearbyListPlaceholders() {
    const viewportStart = this.listTarget.scrollLeft - this.listTarget.clientWidth
    const viewportEnd = this.listTarget.scrollLeft + (this.listTarget.clientWidth * 2)

    this.listPages.forEach((page) => {
      if (!this.listPagePruned(page)) return
      if (this.listPageEnd(page) < viewportStart || this.listPageStart(page) > viewportEnd) return

      this.restoreListPage(page)
    })
  }

  restoreListPage(page) {
    const stored = this.storedListPages.get(page.index)
    if (!stored) return

    page.elements = page.elements.map((placeholder, index) => {
      if (!this.isListPlaceholder(placeholder)) return placeholder

      const template = document.createElement("template")
      template.innerHTML = stored[index] || ""
      const restored = template.content.firstElementChild
      if (!(restored instanceof HTMLElement)) return placeholder

      restored.dataset.homepageLaneListPage = page.index.toString()
      placeholder.replaceWith(restored)
      return restored
    })

    this.storedListPages.delete(page.index)
  }

  nearEnd() {
    if (!this.canLoad) return false

    const remaining = this.trackTarget.scrollWidth - this.trackTarget.clientWidth - this.trackTarget.scrollLeft
    return remaining < this.trackTarget.clientWidth * 1.15
  }

  listNearEnd() {
    if (!this.canLoadListRows || !this.hasListTarget) return false

    const remaining = this.listTarget.scrollWidth - this.listTarget.clientWidth - this.listTarget.scrollLeft
    return remaining < this.listTarget.clientWidth * 1.15
  }

  requestUrl(mode, { cursor = this.cursorValue, perPage = this.perPageValue } = {}) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("lane", this.laneValue)
    url.searchParams.set("cursor", cursor)
    url.searchParams.set("per_page", perPage.toString())
    url.searchParams.set("mode", mode)
    return url.toString()
  }

  appendListRows(html, { appendToInitialPage = false } = {}) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const elements = Array.from(template.content.children).filter((element) => element instanceof HTMLElement)
    if (elements.length === 0) return []

    const page = appendToInitialPage ? this.listPages[0] : null
    const pageIndex = page?.index ?? ++this.listPageIndex
    elements.forEach((element) => {
      element.dataset.homepageLaneListPage = pageIndex.toString()
      this.listContainer.appendChild(element)
    })

    if (page) {
      page.elements.push(...elements)
    } else {
      this.listPages.push({ index: pageIndex, elements })
    }

    return elements
  }

  scrollListByPage(direction) {
    if (!this.hasListTarget) return

    const left = this.listTarget.scrollLeft + (this.listTarget.clientWidth * direction)
    this.listTarget.scrollTo({ left, behavior: "smooth" })
    if (direction > 0 && this.listNearEnd()) this.loadListRows()
  }

  pageStart(page) {
    return Math.min(...page.elements.map((element) => element.offsetLeft))
  }

  pageEnd(page) {
    return Math.max(...page.elements.map((element) => element.offsetLeft + element.offsetWidth))
  }

  pagePruned(page) {
    return page.elements.some((element) => this.isPlaceholder(element))
  }

  isPlaceholder(element) {
    return element.dataset.homepageLanePlaceholder === "true"
  }

  listPageStart(page) {
    return Math.min(...page.elements.map((element) => element.offsetLeft))
  }

  listPageEnd(page) {
    return Math.max(...page.elements.map((element) => element.offsetLeft + element.offsetWidth))
  }

  listPagePruned(page) {
    return page.elements.some((element) => this.isListPlaceholder(element))
  }

  isListPlaceholder(element) {
    return element.dataset.homepageLaneListPlaceholder === "true"
  }

  get canLoad() {
    return this.hasUrlValue && this.hasLaneValue && this.hasCursorValue && this.cursorValue.length > 0
  }

  get canLoadListRows() {
    return this.hasUrlValue && this.hasLaneValue && this.hasListCursorValue && this.listCursorValue.length > 0
  }

  get listVisible() {
    return this.hasListTarget && this.listTarget.offsetParent !== null
  }

  get listRowCount() {
    return this.listTarget.querySelectorAll(".event-listing-card").length
  }

  get listContainer() {
    return this.listTarget.querySelector(".event-listing-grid") || this.listTarget
  }

  get maxRenderedPages() {
    return window.matchMedia("(max-width: 699px)").matches ? this.maxPagesMobileValue : this.maxPagesDesktopValue
  }

  setPending(pending) {
    if (!this.hasLinkTarget) return

    this.linkTarget.setAttribute("aria-disabled", pending ? "true" : "false")
    this.linkTarget.classList.toggle("is-loading", pending)
  }

  updateLink() {
    if (!this.hasLinkTarget) return

    this.linkTarget.hidden = !this.canLoad
  }

  abortPendingRequest() {
    if (!this.abortController) return

    this.abortController.abort()
    this.abortController = null
  }

  abortPendingListRequest() {
    if (!this.listAbortController) return

    this.listAbortController.abort()
    this.listAbortController = null
  }
}

import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, removeSavedEvent, savedEventSlugs } from "../lib/saved_events_storage"

const OVERLAY_OPENED_EVENT = "design-preview:overlay-opened"
const OVERLAY_SOURCE = "saved"

export default class extends Controller {
  static targets = [ "button", "panel", "list", "item", "empty", "footer", "label", "shareStatus" ]
  static values = {
    shareUrl: String,
    url: String
  }

  connect() {
    this.handleSavedEventsChanged = this.handleSavedEventsChanged.bind(this)
    this.handleStorage = this.handleStorage.bind(this)
    this.handlePointerDown = this.handlePointerDown.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleOverlayOpened = this.handleOverlayOpened.bind(this)

    window.addEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.addEventListener("storage", this.handleStorage)
    window.addEventListener(OVERLAY_OPENED_EVENT, this.handleOverlayOpened)
    document.addEventListener("pointerdown", this.handlePointerDown)
    document.addEventListener("keydown", this.handleKeydown)
    this.render()
  }

  disconnect() {
    window.removeEventListener("saved-events:changed", this.handleSavedEventsChanged)
    window.removeEventListener("storage", this.handleStorage)
    window.removeEventListener(OVERLAY_OPENED_EVENT, this.handleOverlayOpened)
    document.removeEventListener("pointerdown", this.handlePointerDown)
    document.removeEventListener("keydown", this.handleKeydown)
    this.itemsAbortController?.abort()
    clearTimeout(this.shareStatusTimeout)
  }

  toggle(event) {
    event.preventDefault()

    if (this.panelTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  async open() {
    this.announceOpen()
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.element.classList.add("is-open")
    await this.loadItems()
    this.render()
  }

  close() {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.element.classList.remove("is-open")
  }

  render() {
    const slugs = savedEventSlugs()
    const savedSlugs = new Set(slugs)
    const currentKey = slugs.join("\n")
    let visibleCount = this.loadedKey === currentKey ? 0 : slugs.length

    if (this.loadedKey === currentKey) {
      this.itemTargets.forEach((item) => {
        const visible = savedSlugs.has(item.dataset.slug)
        item.hidden = !visible
        if (visible) visibleCount += 1
      })
    }

    this.element.classList.toggle("has-saved-events", visibleCount > 0)
    this.buttonTarget.setAttribute(
      "aria-label",
      visibleCount > 0 ? `${visibleCount} gemerkte Events anzeigen` : "Gemerkte Events anzeigen"
    )

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = visibleCount.toString()
    }

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visibleCount > 0
    }

    if (this.hasFooterTarget) {
      this.footerTarget.hidden = visibleCount === 0
    }
  }

  async loadItems() {
    const slugs = savedEventSlugs()
    const currentKey = slugs.join("\n")
    if (this.loadedKey === currentKey || !this.hasListTarget) return

    if (slugs.length === 0 || !this.hasUrlValue) {
      this.listTarget.innerHTML = ""
      this.loadedKey = currentKey
      return
    }

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("mode", "dropdown")
    slugs.forEach((slug) => url.searchParams.append("slugs[]", slug))

    this.itemsAbortController?.abort()
    const abortController = new AbortController()
    this.itemsAbortController = abortController

    try {
      const response = await fetch(url, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
        signal: abortController.signal
      })
      if (!response.ok) return

      const html = await response.text()
      if (savedEventSlugs().join("\n") !== currentKey) return

      this.listTarget.innerHTML = html
      this.loadedKey = currentKey
    } catch (error) {
      if (error.name !== "AbortError") console.error(error)
    } finally {
      if (this.itemsAbortController === abortController) this.itemsAbortController = null
    }
  }

  async share(event) {
    event.preventDefault()

    const url = this.shareUrl()
    const title = "Meine Merkliste bei Stuttgart Live"

    try {
      if (navigator.share) {
        await navigator.share({ title, url })
        this.showShareStatus("Geteilt")
        return
      }

      await navigator.clipboard.writeText(url)
      this.showShareStatus("Link kopiert")
    } catch (error) {
      if (error.name === "AbortError") return

      this.showShareStatus("Kopieren nicht möglich")
    }
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()

    const slug = event.params.slug?.toString()
    if (!slug) return
    if (!removeSavedEvent(slug)) return

    window.dispatchEvent(new CustomEvent("saved-events:changed", {
      detail: {
        saved: false,
        slug
      }
    }))

    this.render()
  }

  shareUrl() {
    const url = new URL(this.hasShareUrlValue ? this.shareUrlValue : window.location.href, window.location.origin)
    url.search = ""

    this.visibleSlugs.forEach((slug) => url.searchParams.append("slugs[]", slug))
    return url.toString()
  }

  showShareStatus(message) {
    if (!this.hasShareStatusTarget) return

    clearTimeout(this.shareStatusTimeout)
    this.shareStatusTarget.textContent = message
    this.shareStatusTarget.hidden = false
    this.shareStatusTimeout = window.setTimeout(() => {
      this.shareStatusTarget.hidden = true
    }, 1800)
  }

  handleStorage(event) {
    if (event.key && event.key !== STORAGE_KEY) return

    this.handleSavedEventsChanged()
  }

  async handleSavedEventsChanged() {
    if (!this.panelTarget.hidden) await this.loadItems()

    this.render()
  }

  handlePointerDown(event) {
    if (this.panelTarget.hidden || this.element.contains(event.target)) return

    this.close()
  }

  handleKeydown(event) {
    if (event.key !== "Escape" || this.panelTarget.hidden) return

    event.preventDefault()
    this.close()
    this.buttonTarget.focus()
  }

  handleOverlayOpened(event) {
    if (event.detail?.source === OVERLAY_SOURCE) return

    this.close()
  }

  announceOpen() {
    window.dispatchEvent(new CustomEvent(OVERLAY_OPENED_EVENT, {
      detail: { source: OVERLAY_SOURCE }
    }))
  }

  get visibleSlugs() {
    return this.itemTargets.filter((item) => !item.hidden).map((item) => item.dataset.slug).filter(Boolean)
  }
}

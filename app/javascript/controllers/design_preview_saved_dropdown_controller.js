import { Controller } from "@hotwired/stimulus"
import { STORAGE_KEY, removeSavedEvent, savedEventSlugs } from "../lib/saved_events_storage"

const OVERLAY_OPENED_EVENT = "design-preview:overlay-opened"
const OVERLAY_SOURCE = "saved"

export default class extends Controller {
  static targets = [ "button", "panel", "item", "empty", "footer", "label", "shareStatus" ]
  static values = {
    shareUrl: String
  }

  connect() {
    this.handleSavedEventsChanged = this.render.bind(this)
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

  open() {
    this.announceOpen()
    this.render()
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.element.classList.add("is-open")
  }

  close() {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.element.classList.remove("is-open")
  }

  render() {
    const slugs = savedEventSlugs()
    const savedSlugs = new Set(slugs)
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const visible = savedSlugs.has(item.dataset.slug)
      item.hidden = !visible
      if (visible) visibleCount += 1
    })

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

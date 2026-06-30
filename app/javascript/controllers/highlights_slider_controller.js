import { Controller } from "@hotwired/stimulus"

const SCROLL_STORAGE_PREFIX = "highlights-slider:scroll"

export default class extends Controller {
  static targets = [ "track", "previousButton", "nextButton", "toggleButton" ]
  static values = {
    autoplay: { type: Boolean, default: false },
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.updateButtons = this.updateButtons.bind(this)
    this.handleTrackScroll = this.handleTrackScroll.bind(this)
    this.handleFocusIn = this.handleFocusIn.bind(this)
    this.handleFocusOut = this.handleFocusOut.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.handleViewportChange = this.handleViewportChange.bind(this)
    this.finishLoopReset = this.finishLoopReset.bind(this)
    this.mobileHeroMediaQuery = window.matchMedia("(max-width: 767px)")
    this.userPaused = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    this.setupLoopClone()
    this.trackTarget?.addEventListener("scroll", this.handleTrackScroll, { passive: true })
    this.handleMouseEnter = () => this.stopAutoplay()
    this.handleMouseLeave = () => this.startAutoplay()
    this.element.addEventListener("mouseenter", this.handleMouseEnter)
    this.element.addEventListener("mouseleave", this.handleMouseLeave)
    this.element.addEventListener("focusin", this.handleFocusIn)
    this.element.addEventListener("focusout", this.handleFocusOut)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    this.mobileHeroMediaQuery.addEventListener("change", this.handleViewportChange)
    this.updateButtons()
    this.updateToggleButton()
    this.handleViewportChange()
    this.restoreScrollPosition()
    window.requestAnimationFrame(() => this.resetMobileHeroTrack())
    this.startAutoplay()
  }

  disconnect() {
    this.trackTarget?.removeEventListener("scroll", this.handleTrackScroll)
    this.element.removeEventListener("mouseenter", this.handleMouseEnter)
    this.element.removeEventListener("mouseleave", this.handleMouseLeave)
    this.element.removeEventListener("focusin", this.handleFocusIn)
    this.element.removeEventListener("focusout", this.handleFocusOut)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.mobileHeroMediaQuery?.removeEventListener("change", this.handleViewportChange)
    this.removeLoopClone()
    this.stopAutoplay()
    this.clearLoopResetTimer()
    this.storeScrollPosition()
    this.clearScrollStoreTimer()
  }

  previous(event) {
    event.preventDefault()
    this.scrollByPage(-1)
  }

  next(event) {
    event.preventDefault()
    this.scrollByPage(1)
  }

  toggleAutoplay(event) {
    event.preventDefault()
    this.userPaused = !this.userPaused

    if (this.userPaused) {
      this.stopAutoplay()
    } else {
      this.startAutoplay()
    }

    this.updateToggleButton()
  }

  scrollByPage(direction) {
    const items = this.sliderItems()
    if (items.length === 0) return

    if (direction > 0 && this.atEnd()) {
      if (this.requestHomepageLanePage()) return

      this.returnToStart()
      return
    }

    const columns = this.sliderColumns(items)
    const currentIndex = this.leadingVisibleColumnIndex(columns)
    const pageSize = this.visibleColumnCount(columns)
    const targetIndex = this.clampIndex(currentIndex + (pageSize * direction), columns)

    if (direction > 0 && targetIndex === currentIndex && this.requestHomepageLanePage()) return

    this.scrollToColumn(columns[targetIndex])
  }

  updateButtons() {
    if (!this.hasTrackTarget) return

    const maxScrollLeft = this.trackTarget.scrollWidth - this.trackTarget.clientWidth
    const currentScroll = this.trackTarget.scrollLeft

    if (this.hasPreviousButtonTarget) {
      this.previousButtonTarget.disabled = currentScroll <= 4
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.disabled = maxScrollLeft <= 4 && !this.canRequestHomepageLanePage()
    }
  }

  handleTrackScroll() {
    this.updateButtons()
    this.queueStoreScrollPosition()
  }

  startAutoplay() {
    if (!this.autoplayValue || !this.hasTrackTarget) return
    if (!this.autoplayAllowed()) return
    if (this.userPaused || document.hidden) return
    if (this.autoplayTimer) return

    this.autoplayTimer = window.setInterval(() => {
      const items = this.sliderItems()
      if (items.length === 0) return

      if (this.loopClone && this.leadingVisibleIndex(items) >= items.length - 1) {
        this.scrollToLoopClone()
      } else {
        this.scrollBySingleItem()
      }
    }, this.intervalValue)
  }

  scrollBySingleItem() {
    const items = this.sliderItems()
    if (items.length === 0) return

    const currentIndex = this.leadingVisibleIndex(items)
    const targetIndex = this.clampIndex(currentIndex + 1, items)
    this.scrollToItem(items[targetIndex])
  }

  sliderItems() {
    if (!this.hasTrackTarget) return []

    return Array.from(this.trackTarget.children).filter((item) => (
      item instanceof HTMLElement && item.dataset.highlightsSliderClone !== "true"
    ))
  }

  leadingVisibleIndex(items) {
    const currentScroll = this.trackTarget.scrollLeft

    for (let index = 0; index < items.length; index += 1) {
      const item = items[index]
      if ((item.offsetLeft + item.offsetWidth) > currentScroll + 4) {
        return index
      }
    }

    return Math.max(0, items.length - 1)
  }

  visibleItemCount(items) {
    const viewportStart = this.trackTarget.scrollLeft + 4
    const viewportEnd = viewportStart + this.trackTarget.clientWidth - 8
    let count = 0

    items.forEach((item) => {
      const itemStart = item.offsetLeft
      const itemEnd = itemStart + item.offsetWidth
      if (itemEnd > viewportStart && itemStart < viewportEnd) count += 1
    })

    return Math.max(count, 1)
  }

  sliderColumns(items) {
    const columns = []
    const tolerance = 2

    items.forEach((item) => {
      const left = item.offsetLeft
      const width = item.offsetWidth
      const existingColumn = columns.find((column) => Math.abs(column.left - left) <= tolerance)

      if (existingColumn) {
        existingColumn.right = Math.max(existingColumn.right, left + width)
      } else {
        columns.push({ left, right: left + width })
      }
    })

    return columns.sort((a, b) => a.left - b.left)
  }

  leadingVisibleColumnIndex(columns) {
    const currentScroll = this.trackTarget.scrollLeft

    for (let index = 0; index < columns.length; index += 1) {
      if (columns[index].right > currentScroll + 4) {
        return index
      }
    }

    return Math.max(0, columns.length - 1)
  }

  visibleColumnCount(columns) {
    const viewportStart = this.trackTarget.scrollLeft + 4
    const viewportEnd = viewportStart + this.trackTarget.clientWidth - 8
    const count = columns.filter((column) => column.right > viewportStart && column.left < viewportEnd).length

    return Math.max(count, 1)
  }

  clampIndex(index, items) {
    return Math.max(0, Math.min(index, items.length - 1))
  }

  scrollToItem(item) {
    if (!(item instanceof HTMLElement)) return

    this.trackTarget.scrollTo({ left: Math.round(item.offsetLeft), behavior: "smooth" })
  }

  scrollToColumn(column) {
    if (!column) return

    this.trackTarget.scrollTo({ left: Math.round(column.left), behavior: "smooth" })
  }

  returnToStart() {
    this.trackTarget.scrollTo({ left: 0, behavior: "auto" })
  }

  setupLoopClone() {
    if (!this.loopCloneAllowed()) return

    const firstItem = this.trackTarget.children[0]
    if (!(firstItem instanceof HTMLElement)) return

    this.loopClone = firstItem.cloneNode(true)
    this.loopClone.dataset.highlightsSliderClone = "true"
    this.loopClone.setAttribute("aria-hidden", "true")
    this.loopClone.querySelectorAll("[id]").forEach((element) => element.removeAttribute("id"))
    this.loopClone.querySelectorAll("a, button, input, select, textarea, [tabindex]").forEach((element) => {
      element.setAttribute("tabindex", "-1")
    })

    if ("inert" in this.loopClone) {
      this.loopClone.inert = true
    }

    this.trackTarget.appendChild(this.loopClone)
  }

  removeLoopClone() {
    this.loopClone?.remove()
    this.loopClone = null
  }

  loopCloneAllowed() {
    return this.autoplayValue &&
      this.hasTrackTarget &&
      this.element.matches(".promotion-banner-slider-section") &&
      this.trackTarget.children.length > 1
  }

  scrollToLoopClone() {
    if (!this.loopClone) {
      this.returnToStart()
      return
    }

    this.pendingLoopReset = true
    this.trackTarget.addEventListener("scrollend", this.finishLoopReset, { once: true })
    this.trackTarget.scrollTo({ left: Math.round(this.loopClone.offsetLeft), behavior: "smooth" })
    this.loopResetTimer = window.setTimeout(this.finishLoopReset, 900)
  }

  finishLoopReset() {
    if (!this.pendingLoopReset) return

    this.pendingLoopReset = false
    this.trackTarget?.removeEventListener("scrollend", this.finishLoopReset)
    this.clearLoopResetTimer()
    this.returnToStart()
    this.updateButtons()
  }

  clearLoopResetTimer() {
    window.clearTimeout(this.loopResetTimer)
    this.loopResetTimer = null
  }

  atEnd() {
    if (!this.hasTrackTarget) return false

    const maxScrollLeft = this.trackTarget.scrollWidth - this.trackTarget.clientWidth
    return this.trackTarget.scrollLeft >= maxScrollLeft - 4
  }

  requestHomepageLanePage() {
    if (!this.canRequestHomepageLanePage()) return false

    const event = new CustomEvent("homepage-lane:load", {
      bubbles: true,
      cancelable: true,
      detail: { advance: true }
    })
    this.element.dispatchEvent(event)

    return true
  }

  canRequestHomepageLanePage() {
    return this.element.matches("[data-controller~='homepage-lane']") &&
      (
        this.element.dataset.homepageLaneDeferredValue === "true" ||
        (this.element.dataset.homepageLaneCursorValue || "").length > 0
      )
  }

  stopAutoplay() {
    if (!this.autoplayTimer) return

    window.clearInterval(this.autoplayTimer)
    this.autoplayTimer = null
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return

    this.toggleButtonTarget.textContent = this.userPaused ? "Animation starten" : "Animation pausieren"
    this.toggleButtonTarget.setAttribute("aria-pressed", this.userPaused ? "true" : "false")
  }

  handleFocusIn() {
    this.stopAutoplay()
  }

  handleFocusOut() {
    window.requestAnimationFrame(() => {
      if (this.element.contains(document.activeElement)) return
      this.startAutoplay()
    })
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stopAutoplay()
    } else {
      this.startAutoplay()
    }
  }

  autoplayAllowed() {
    return true
  }

  handleViewportChange() {
    if (!this.hasTrackTarget) return
    if (this.isMobileHeroSlider()) {
      this.resetMobileHeroTrack()
    }

    this.stopAutoplay()
    this.startAutoplay()
    this.updateButtons()
  }

  resetMobileHeroTrack() {
    if (!this.isMobileHeroSlider()) return

    const resetTrackPosition = () => {
      if (!this.hasTrackTarget) return
      this.trackTarget.scrollLeft = 0
      this.trackTarget.scrollTo({ left: 0, behavior: "auto" })
      this.updateButtons()
    }

    resetTrackPosition()
    window.requestAnimationFrame(() => {
      resetTrackPosition()
      window.requestAnimationFrame(resetTrackPosition)
    })
    window.setTimeout(resetTrackPosition, 120)
  }

  isMobileHeroSlider() {
    return this.hasTrackTarget &&
      this.mobileHeroMediaQuery?.matches &&
      this.element.matches(".promotion-banner-slider-section--hero")
  }

  queueStoreScrollPosition() {
    if (!this.shouldRememberScrollPosition()) return

    window.clearTimeout(this.scrollStoreTimer)
    this.scrollStoreTimer = window.setTimeout(() => this.storeScrollPosition(), 80)
  }

  storeScrollPosition() {
    if (!this.shouldRememberScrollPosition()) return

    const scrollLeft = Math.round(this.trackTarget.scrollLeft)
    if (scrollLeft <= 0) {
      window.sessionStorage.removeItem(this.scrollStorageKey())
      return
    }

    window.sessionStorage.setItem(this.scrollStorageKey(), String(scrollLeft))
  }

  restoreScrollPosition() {
    if (!this.shouldRememberScrollPosition()) return

    const storedScroll = Number.parseInt(window.sessionStorage.getItem(this.scrollStorageKey()), 10)
    if (!Number.isFinite(storedScroll) || storedScroll <= 0) return

    const restore = () => {
      if (!this.hasTrackTarget) return
      this.trackTarget.scrollLeft = storedScroll
      this.trackTarget.scrollTo({ left: storedScroll, behavior: "auto" })
      this.updateButtons()
    }

    window.requestAnimationFrame(() => {
      restore()
      window.requestAnimationFrame(restore)
    })
  }

  shouldRememberScrollPosition() {
    return this.hasTrackTarget && !this.isMobileHeroSlider()
  }

  scrollStorageKey() {
    const pageKey = `${window.location.pathname}${window.location.search}`
    const sliderKey = this.element.dataset.homepageLaneLaneValue ||
      this.element.querySelector(".lane-header h2, .highlights-slider-header h2")?.textContent?.trim() ||
      this.sliderIndex()

    return `${SCROLL_STORAGE_PREFIX}:${pageKey}:${sliderKey}`
  }

  sliderIndex() {
    return Array.from(document.querySelectorAll("[data-controller~='highlights-slider']")).indexOf(this.element)
  }

  clearScrollStoreTimer() {
    window.clearTimeout(this.scrollStoreTimer)
    this.scrollStoreTimer = null
  }
}

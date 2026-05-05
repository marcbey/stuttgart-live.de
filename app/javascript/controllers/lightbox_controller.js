import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "image", "caption", "item", "previousButton", "nextButton", "closeButton" ]

  connect() {
    this.currentIndex = -1
    this.swipeState = null
    this.suppressNextClick = false
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  open(event) {
    event.preventDefault()

    const trigger = event.currentTarget
    this.currentIndex = this.itemTargets.indexOf(trigger)
    if (this.currentIndex < 0) return

    this.lastFocusedElement = trigger
    this.renderCurrentItem()

    this.dialogTarget.hidden = false
    document.body.classList.add("lightbox-open")
    document.addEventListener("keydown", this.handleKeydown)
    window.requestAnimationFrame(() => this.focusFirstElement())
  }

  close() {
    if (!this.hasDialogTarget || !this.hasImageTarget) return

    this.swipeState = null
    this.suppressNextClick = false
    this.dialogTarget.hidden = true
    this.imageTarget.removeAttribute("src")
    this.imageTarget.alt = ""
    document.body.classList.remove("lightbox-open")
    document.removeEventListener("keydown", this.handleKeydown)
    this.restoreFocus()
  }

  previous(event) {
    event.preventDefault()
    this.showPrevious()
  }

  next(event) {
    event.preventDefault()
    this.showNext()
  }

  backdropClose(event) {
    if (this.suppressNextClick) {
      this.suppressClick(event)
      return
    }

    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  pointerDown(event) {
    if (this.itemTargets.length <= 1) return
    if (event.pointerType === "mouse" && event.button !== 0) return

    this.swipeState = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      currentX: event.clientX,
      currentY: event.clientY
    }
  }

  pointerMove(event) {
    if (!this.swipeState || event.pointerId !== this.swipeState.pointerId) return

    this.swipeState.currentX = event.clientX
    this.swipeState.currentY = event.clientY

    const deltaX = event.clientX - this.swipeState.startX
    const deltaY = event.clientY - this.swipeState.startY
    if (this.isHorizontalSwipe(deltaX, deltaY, 12)) {
      event.preventDefault()
    }
  }

  pointerUp(event) {
    if (!this.swipeState || event.pointerId !== this.swipeState.pointerId) return

    const { startX, startY } = this.swipeState
    this.swipeState = null

    const deltaX = event.clientX - startX
    const deltaY = event.clientY - startY
    const swipeThreshold = Math.min(80, Math.max(36, this.dialogTarget.clientWidth * 0.12))
    if (!this.isHorizontalSwipe(deltaX, deltaY, swipeThreshold)) return

    this.suppressNextClick = true
    event.preventDefault()

    if (deltaX < 0) {
      this.showNext()
    } else {
      this.showPrevious()
    }
  }

  pointerCancel(event) {
    if (!this.swipeState || event.pointerId !== this.swipeState.pointerId) return

    this.swipeState = null
  }

  suppressClick(event) {
    if (!this.suppressNextClick) return

    this.suppressNextClick = false
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "Tab") {
      this.maintainFocus(event)
    } else if (event.key === "ArrowLeft") {
      this.previous(event)
    } else if (event.key === "ArrowRight") {
      this.next(event)
    }
  }

  renderCurrentItem() {
    if (!this.hasImageTarget) return

    const trigger = this.itemTargets[this.currentIndex]
    if (!trigger) return

    const src = trigger.dataset.lightboxSrcValue
    const alt = trigger.dataset.lightboxAltValue || ""
    const caption = trigger.dataset.lightboxCaptionValue || ""
    if (!src) return

    this.imageTarget.src = src
    this.imageTarget.alt = alt

    if (this.hasCaptionTarget) {
      this.captionTarget.textContent = caption
      this.captionTarget.hidden = caption.length === 0
    }

    if (this.hasPreviousButtonTarget) {
      this.previousButtonTarget.disabled = this.currentIndex <= 0
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.disabled = this.currentIndex >= this.itemTargets.length - 1
    }
  }

  showPrevious() {
    if (this.currentIndex <= 0) return

    this.currentIndex -= 1
    this.renderCurrentItem()
  }

  showNext() {
    if (this.currentIndex >= this.itemTargets.length - 1) return

    this.currentIndex += 1
    this.renderCurrentItem()
  }

  isHorizontalSwipe(deltaX, deltaY, threshold) {
    return Math.abs(deltaX) >= threshold && Math.abs(deltaX) > Math.abs(deltaY) * 1.2
  }

  focusFirstElement() {
    const [firstElement] = this.focusableElements()
    ;(firstElement || this.dialogTarget)?.focus()
  }

  restoreFocus() {
    if (this.lastFocusedElement?.isConnected) {
      this.lastFocusedElement.focus()
    }
  }

  maintainFocus(event) {
    const focusableElements = this.focusableElements()
    if (focusableElements.length === 0) {
      event.preventDefault()
      this.dialogTarget.focus()
      return
    }

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault()
      lastElement.focus()
    } else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  focusableElements() {
    return Array.from(this.dialogTarget.querySelectorAll([
      "button:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(","))).filter((element) => element instanceof HTMLElement && !element.hidden)
  }
}

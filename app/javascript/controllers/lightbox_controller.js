import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "image", "caption", "item", "previousButton", "nextButton", "closeButton" ]

  connect() {
    this.currentIndex = -1
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

    this.dialogTarget.hidden = true
    this.imageTarget.removeAttribute("src")
    this.imageTarget.alt = ""
    document.body.classList.remove("lightbox-open")
    document.removeEventListener("keydown", this.handleKeydown)
    this.restoreFocus()
  }

  previous(event) {
    event.preventDefault()
    if (this.currentIndex <= 0) return

    this.currentIndex -= 1
    this.renderCurrentItem()
  }

  next(event) {
    event.preventDefault()
    if (this.currentIndex >= this.itemTargets.length - 1) return

    this.currentIndex += 1
    this.renderCurrentItem()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
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

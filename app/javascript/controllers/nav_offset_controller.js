import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.updateOffset = this.updateOffset.bind(this)
    this.resizeObserver = new ResizeObserver(this.updateOffset)
    this.resizeObserver.observe(this.element)
    this.updateOffset()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  updateOffset() {
    const navHeight = Math.ceil(this.element.getBoundingClientRect().height)
    document.documentElement.style.setProperty("--app-nav-height", `${navHeight}px`)
  }
}

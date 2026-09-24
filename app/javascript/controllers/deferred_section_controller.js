import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]
  static values = { url: String }

  connect() {
    this.loading = false
    this.installObserver()
  }

  disconnect() {
    this.observer?.disconnect()
    this.abortController?.abort()
  }

  installObserver() {
    if (!("IntersectionObserver" in window)) {
      this.load()
      return
    }

    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.load()
    }, { rootMargin: "900px 0px" })
    this.observer.observe(this.element)
  }

  async load() {
    if (this.loading || !this.hasUrlValue) return

    this.loading = true
    this.abortController = new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`Deferred section request failed (${response.status})`)

      this.contentTarget.innerHTML = await response.text()
      this.element.classList.add("is-loaded")
      this.observer?.disconnect()
    } catch (error) {
      if (error.name !== "AbortError") this.loading = false
    }
  }
}

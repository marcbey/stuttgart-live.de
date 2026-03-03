import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.loading = false
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) this.load()
      })
    }, { rootMargin: "200px 0px" })

    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async load() {
    if (this.loading || !this.hasUrlValue || this.urlValue.length === 0) return

    this.loading = true
    const nextUrl = this.urlValue
    this.urlValue = ""

    try {
      const response = await fetch(nextUrl, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })

      if (!response.ok) return

      const html = await response.text()
      Turbo.renderStreamMessage(html)
    } finally {
      this.loading = false
    }
  }
}

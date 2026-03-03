import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.handler = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.handler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handler)
  }

  onKeydown(event) {
    if (this.typing(event.target)) return

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
      event.preventDefault()
      const form = document.querySelector("#event_editor form")
      form?.requestSubmit()
      return
    }

    if (event.key !== "j" && event.key !== "k") return

    const links = Array.from(document.querySelectorAll(".event-link"))
    if (links.length === 0) return

    const active = document.querySelector(".event-list-item-active .event-link")
    const index = active ? links.indexOf(active) : 0
    const nextIndex = event.key === "j" ? Math.min(index + 1, links.length - 1) : Math.max(index - 1, 0)
    const target = links[nextIndex]

    if (target) {
      event.preventDefault()
      target.click()
    }
  }

  typing(target) {
    if (!(target instanceof HTMLElement)) return false

    return ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) || target.isContentEditable
  }
}

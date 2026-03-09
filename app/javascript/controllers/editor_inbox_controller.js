import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedContext", "headerActions"]

  connect() {
    this.syncActiveFromEditor()
  }

  itemLinkClicked(event) {
    const itemId = event.currentTarget?.dataset?.editorInboxItemId
    this.highlightItem(itemId)
  }

  syncActiveFromEditor(event) {
    const frame = event?.target
    if (frame && frame.id !== "blog_editor") return

    this.syncSelectedContext()
    this.syncHeaderActions()

    const editorPanel = document.querySelector("turbo-frame#blog_editor .editor-panel")
    this.highlightItem(editorPanel?.dataset?.selectedItemId)
  }

  syncActiveAfterSubmit(event) {
    if (!event?.detail?.success) return

    const target = event.target
    if (!(target instanceof HTMLFormElement)) return
    if (!target.id.endsWith("_editor_form")) return

    window.requestAnimationFrame(() => this.syncActiveFromEditor())
  }

  syncSelectedContext() {
    if (!this.hasSelectedContextTarget) return

    const editorPanel = document.querySelector("turbo-frame#blog_editor .editor-panel")
    this.selectedContextTarget.textContent = editorPanel?.dataset?.selectedContext?.trim() || ""
  }

  syncHeaderActions() {
    if (!this.hasHeaderActionsTarget) return

    const template = document.querySelector("turbo-frame#blog_editor .editor-actions-template")
    this.headerActionsTarget.replaceChildren()
    if (!(template instanceof HTMLTemplateElement)) return

    this.headerActionsTarget.append(template.content.cloneNode(true))
  }

  highlightItem(itemId) {
    const items = Array.from(document.querySelectorAll(".blog-list-item"))
    items.forEach((item) => item.classList.remove("event-list-item-active"))

    if (!itemId) return

    const activeLink = document.querySelector(`.blog-link[data-editor-inbox-item-id='${itemId}']`)
    const activeItem = activeLink?.closest(".blog-list-item")
    if (activeItem) activeItem.classList.add("event-list-item-active")
  }
}

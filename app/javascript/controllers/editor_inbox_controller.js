import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["headerActions", "newAction"]
  static values = {
    frameId: { type: String, default: "blog_editor" },
    itemSelector: { type: String, default: ".blog-list-item" },
    linkSelector: { type: String, default: ".blog-link" },
    itemIdAttribute: { type: String, default: "editorInboxItemId" }
  }

  connect() {
    this.syncActiveFromEditor()
  }

  itemLinkClicked(event) {
    const itemId = this.itemIdFrom(event.currentTarget)
    this.highlightItem(itemId)
  }

  syncActiveFromEditor(event) {
    const frame = event?.target
    if (frame && frame.id !== this.frameIdValue) return

    this.syncHeaderActions()

    const editorPanel = document.querySelector(`turbo-frame#${this.frameIdValue} .editor-panel`)
    this.syncNewActionVisibility(editorPanel)
    this.highlightItem(editorPanel?.dataset?.selectedItemId)
  }

  syncActiveAfterSubmit(event) {
    if (!event?.detail?.success) return

    const target = event.target
    if (!(target instanceof HTMLFormElement)) return
    if (!target.id.startsWith("editor_form_")) return
    if (!target.closest(`turbo-frame#${this.frameIdValue}`)) return

    window.requestAnimationFrame(() => this.syncActiveFromEditor())
  }

  syncHeaderActions() {
    if (!this.hasHeaderActionsTarget) return

    const template = document.querySelector(`turbo-frame#${this.frameIdValue} .editor-actions-template`)
    this.headerActionsTarget.replaceChildren()
    if (!(template instanceof HTMLTemplateElement)) return

    this.headerActionsTarget.append(template.content.cloneNode(true))
  }

  syncNewActionVisibility(editorPanel) {
    if (!this.hasNewActionTarget) return

    const hideNewAction = editorPanel instanceof HTMLElement && !editorPanel.dataset.selectedItemId
    this.newActionTargets.forEach((element) => {
      element.hidden = hideNewAction
    })
  }

  highlightItem(itemId) {
    const items = Array.from(document.querySelectorAll(this.itemSelectorValue))
    items.forEach((item) => item.classList.remove("event-list-item-active"))

    if (!itemId) return

    const activeLink = Array.from(document.querySelectorAll(this.linkSelectorValue))
      .find((link) => this.itemIdFrom(link) === String(itemId))
    const activeItem = activeLink?.closest(this.itemSelectorValue)
    if (activeItem) activeItem.classList.add("event-list-item-active")
  }

  itemIdFrom(element) {
    if (!(element instanceof HTMLElement)) return null

    return element.dataset?.[this.itemIdAttributeValue]
  }
}

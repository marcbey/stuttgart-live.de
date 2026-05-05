import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["headerActions", "newAction"]
  static values = {
    frameId: { type: String, default: "blog_editor" },
    itemSelector: { type: String, default: ".blog-list-item" },
    linkSelector: { type: String, default: ".blog-link" },
    itemIdAttribute: { type: String, default: "editorInboxItemId" },
    defaultEditorTab: { type: String, default: "" }
  }

  connect() {
    this.syncActiveFromEditor()
  }

  itemLinkClicked(event) {
    const editorTab = this.currentEditorTab()
    this.applyEditorTabToLink(event.currentTarget, editorTab)
    this.pushSelectionUrl(event, editorTab)

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

  currentEditorTab() {
    return document.querySelector(`turbo-frame#${this.frameIdValue} input[name='editor_tab']`)?.value || null
  }

  applyEditorTabToLink(link, editorTab) {
    if (!(link instanceof HTMLAnchorElement)) return

    const url = new URL(link.href, window.location.origin)
    this.applyEditorTabToUrl(url, editorTab)
    link.href = url.toString()
  }

  applyEditorTabToUrl(url, editorTab) {
    if (editorTab && editorTab !== this.defaultEditorTabValue) {
      url.searchParams.set("editor_tab", editorTab)
    } else {
      url.searchParams.delete("editor_tab")
    }
  }

  pushSelectionUrl(event, editorTab = null) {
    if (event.defaultPrevented || event.button !== 0) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const link = event.currentTarget
    if (!(link instanceof HTMLAnchorElement)) return
    if (link.target && link.target !== "_self") return

    const selectionUrl = link.dataset.editorInboxSelectionUrl
    if (!selectionUrl) return

    const nextUrl = new URL(selectionUrl, window.location.href)
    if (nextUrl.origin !== window.location.origin) return
    this.applyEditorTabToUrl(nextUrl, editorTab)
    if (`${nextUrl.pathname}${nextUrl.search}${nextUrl.hash}` === `${window.location.pathname}${window.location.search}${window.location.hash}`) return

    window.history.pushState(window.history.state, "", nextUrl)
  }
}

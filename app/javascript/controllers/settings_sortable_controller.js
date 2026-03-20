import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "item", "index" ]

  connect() {
    this.syncSelectionState()
  }

  dragstart(event) {
    const item = this.findItem(event)
    if (!item) return

    this.draggedItem = item
    this.draggedItem.classList.add("settings-reference-item-dragging")

    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", item.dataset.settingsSortableId || "")
    }
  }

  dragenter(event) {
    if (!this.draggedItem) return

    event.preventDefault()
  }

  dragover(event) {
    if (!this.draggedItem) return

    event.preventDefault()

    const targetItem = this.findItem(event)
    if (!this.validDropTarget(targetItem)) {
      this.clearDropMarker()
      return
    }

    const insertBefore = this.insertBeforeTarget(event, targetItem)
    if (this.shouldKeepSelectedItemsStable(targetItem, insertBefore)) {
      this.clearDropMarker()
      return
    }

    this.dropTarget = targetItem
    this.dropBefore = insertBefore
    this.renderDropMarker()
  }

  drop(event) {
    if (!this.draggedItem) return

    event.preventDefault()

    if (!this.validDropTarget(this.dropTarget)) return

    this.dropTarget.parentNode.insertBefore(
      this.draggedItem,
      this.dropBefore ? this.dropTarget : this.dropTarget.nextSibling
    )
    this.syncSelectionState()
  }

  dragend() {
    if (!this.draggedItem) return

    this.clearDropMarker()
    this.draggedItem.classList.remove("settings-reference-item-dragging")
    this.draggedItem = null
    this.dropTarget = null
    this.dropBefore = null
    this.syncSelectionState()
  }

  findItem(event) {
    return event.target.closest("[data-settings-sortable-target='item']")
  }

  insertBeforeTarget(event, targetItem) {
    const rect = targetItem.getBoundingClientRect()
    const beforeHalfY = event.clientY < rect.top + (rect.height / 2)
    const beforeHalfX = event.clientX < rect.left + (rect.width / 2)

    return beforeHalfY || beforeHalfX
  }

  shouldKeepSelectedItemsStable(targetItem, insertBefore) {
    if (this.isSelected(this.draggedItem)) return !this.isSelected(targetItem)
    if (this.isSelected(targetItem)) return false

    const currentItems = this.itemTargets
    const reorderedItems = currentItems.filter((item) => item !== this.draggedItem)
    let insertionIndex = reorderedItems.indexOf(targetItem)
    if (insertionIndex < 0) return false
    if (!insertBefore) insertionIndex += 1

    reorderedItems.splice(insertionIndex, 0, this.draggedItem)

    const selectedItems = currentItems.filter((item) => this.isSelected(item))

    return selectedItems.some((item) => currentItems.indexOf(item) !== reorderedItems.indexOf(item))
  }

  isSelected(item) {
    return item?.querySelector("input[type='checkbox']")?.checked === true
  }

  syncSelectionState() {
    let selectedIndex = 0

    this.itemTargets.forEach((item) => {
      const indexElement = item.querySelector("[data-settings-sortable-target='index']")
      if (!indexElement) return

      if (this.isSelected(item)) {
        selectedIndex += 1
        item.dataset.selected = "true"
        indexElement.textContent = String(selectedIndex)
        indexElement.hidden = false
      } else {
        item.dataset.selected = "false"
        indexElement.textContent = ""
        indexElement.hidden = true
      }
    })
  }

  validDropTarget(targetItem) {
    return targetItem && targetItem !== this.draggedItem
  }

  renderDropMarker() {
    this.clearDropMarker()
    if (!this.dropTarget) return

    this.dropTarget.classList.add(this.dropBefore ? "settings-reference-item-drop-before" : "settings-reference-item-drop-after")
  }

  clearDropMarker() {
    this.itemTargets.forEach((item) => {
      item.classList.remove("settings-reference-item-drop-before", "settings-reference-item-drop-after")
    })
  }
}

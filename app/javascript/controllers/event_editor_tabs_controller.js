import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "stateInput", "tab"]
  static values = { initialTab: String }

  connect() {
    this.showTab(this.currentTab(), { focus: false })
  }

  activate(event) {
    event.preventDefault()
    this.showTab(event.params.tabKey)
  }

  keydown(event) {
    const currentIndex = this.tabTargets.indexOf(event.currentTarget)
    if (currentIndex < 0) return

    let nextIndex = currentIndex

    switch (event.key) {
    case "ArrowRight":
    case "ArrowDown":
      nextIndex = (currentIndex + 1) % this.tabTargets.length
      break
    case "ArrowLeft":
    case "ArrowUp":
      nextIndex = (currentIndex - 1 + this.tabTargets.length) % this.tabTargets.length
      break
    case "Home":
      nextIndex = 0
      break
    case "End":
      nextIndex = this.tabTargets.length - 1
      break
    case "Enter":
    case " ":
      event.preventDefault()
      this.showTab(event.currentTarget.dataset.eventEditorTabsTabKeyParam)
      return
    default:
      return
    }

    event.preventDefault()
    const nextTab = this.tabTargets[nextIndex]
    if (!nextTab) return

    this.showTab(nextTab.dataset.eventEditorTabsTabKeyParam, { focus: true })
  }

  showTab(tabKey, options = {}) {
    const { focus = true } = options
    const nextTab = this.findTab(tabKey) || this.tabTargets[0]
    if (!nextTab) return

    const resolvedKey = nextTab.dataset.eventEditorTabsTabKeyParam

    this.tabTargets.forEach((tab) => {
      const active = tab === nextTab
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
      tab.classList.toggle("is-active", active)
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.eventEditorTabsPanelKey === resolvedKey
      panel.hidden = !active
      panel.classList.toggle("is-active", active)
    })

    if (this.hasStateInputTarget) {
      this.stateInputTarget.value = resolvedKey
    }

    if (focus) {
      nextTab.focus()
    }
  }

  currentTab() {
    const candidate = this.initialTabValue || this.stateInputTarget?.value
    return this.findTab(candidate) ? candidate : this.tabTargets[0]?.dataset.eventEditorTabsTabKeyParam
  }

  findTab(tabKey) {
    return this.tabTargets.find((tab) => tab.dataset.eventEditorTabsTabKeyParam === tabKey)
  }
}

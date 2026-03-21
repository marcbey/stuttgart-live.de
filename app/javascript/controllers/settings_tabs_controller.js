import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "panel", "tab" ]
  static values = {
    initialSection: String,
    sectionUrlTemplate: String
  }

  connect() {
    this.handlePopState = this.handlePopState.bind(this)
    window.addEventListener("popstate", this.handlePopState)
    this.showSection(this.currentSection(), { updateHistory: false, focus: false })
  }

  disconnect() {
    window.removeEventListener("popstate", this.handlePopState)
  }

  async activate(event) {
    event.preventDefault()

    const sectionKey = event.currentTarget.dataset.settingsTabsSectionKey
    await this.showSection(sectionKey)
  }

  async keydown(event) {
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
      await this.showSection(event.currentTarget.dataset.settingsTabsSectionKey)
      return
    default:
      return
    }

    event.preventDefault()
    const nextTab = this.tabTargets[nextIndex]
    if (!nextTab) return

    await this.showSection(nextTab.dataset.settingsTabsSectionKey, { focus: true })
  }

  async handlePopState() {
    await this.showSection(this.currentSection(), { updateHistory: false, focus: false })
  }

  async showSection(sectionKey, options = {}) {
    const { focus = true, updateHistory = true } = options
    const tab = this.findTab(sectionKey)
    const panel = this.findPanel(sectionKey)
    if (!tab || !panel) return

    if (panel.dataset.loaded != "true") {
      const loaded = await this.loadPanel(sectionKey, panel, tab.href)
      if (!loaded) return
    }

    this.tabTargets.forEach((item) => {
      const active = item === tab
      item.setAttribute("aria-selected", active ? "true" : "false")
      item.setAttribute("tabindex", active ? "0" : "-1")
      item.classList.toggle("is-active", active)
    })

    this.panelTargets.forEach((item) => {
      item.hidden = item !== panel
      item.classList.toggle("is-active", item === panel)
    })

    if (updateHistory) {
      window.history.pushState({}, "", this.buildEditUrl(tab.dataset.settingsTabsSectionKey))
    }

    if (focus) {
      tab.focus()
    }
  }

  async loadPanel(sectionKey, panel, fallbackUrl) {
    panel.dataset.loading = "true"
    panel.setAttribute("aria-busy", "true")

    try {
      const response = await fetch(this.sectionUrl(sectionKey), {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Unexpected response: ${response.status}`)

      panel.innerHTML = await response.text()
      panel.dataset.loaded = "true"
      return true
    } catch (error) {
      window.location.href = fallbackUrl || this.buildEditUrl(sectionKey)
      return false
    } finally {
      delete panel.dataset.loading
      panel.removeAttribute("aria-busy")
    }
  }

  currentSection() {
    const params = new URL(window.location.href).searchParams
    return params.get("section") || this.initialSectionValue
  }

  sectionUrl(sectionKey) {
    return this.sectionUrlTemplateValue.replace("__SECTION__", encodeURIComponent(sectionKey))
  }

  buildEditUrl(sectionKey) {
    const url = new URL(window.location.href)
    url.searchParams.set("section", sectionKey)
    return url.toString()
  }

  findTab(sectionKey) {
    return this.tabTargets.find((tab) => tab.dataset.settingsTabsSectionKey === sectionKey)
  }

  findPanel(sectionKey) {
    return this.panelTargets.find((panel) => panel.dataset.settingsTabsSectionKey === sectionKey)
  }
}

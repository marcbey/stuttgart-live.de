import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["copyButton", "downloadButton", "source", "status"]
  static values = { filename: String }

  connect() {
    this.defaultCopyButtonLabel = this.hasCopyButtonTarget ?
      (this.copyButtonTarget.getAttribute("aria-label") || "In Zwischenablage kopieren") :
      "In Zwischenablage kopieren"
    this.defaultDownloadButtonLabel = this.hasDownloadButtonTarget ?
      (this.downloadButtonTarget.getAttribute("aria-label") || "Payload herunterladen") :
      "Payload herunterladen"
  }

  disconnect() {
    window.clearTimeout(this.copyResetTimer)
    window.clearTimeout(this.downloadResetTimer)
  }

  async copy(event) {
    event.preventDefault()
    event.stopPropagation()

    try {
      await this.writeText(this.sourceTarget.textContent)
      this.showCopiedState()
    } catch (error) {
      this.showErrorState()
      console.error("Clipboard copy failed", error)
    }
  }

  download(event) {
    event.preventDefault()
    event.stopPropagation()

    try {
      const blob = new Blob([this.sourceTarget.textContent], { type: "application/json;charset=utf-8" })
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")

      link.href = url
      link.download = this.filenameValue || "payload.json"
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      URL.revokeObjectURL(url)

      this.showDownloadedState()
    } catch (error) {
      this.showErrorState("Download fehlgeschlagen.")
      console.error("Payload download failed", error)
    }
  }

  async writeText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    this.copyWithFallback(text)
  }

  copyWithFallback(text) {
    const element = document.createElement("textarea")
    element.value = text
    element.setAttribute("readonly", "")
    element.style.position = "absolute"
    element.style.left = "-9999px"

    document.body.appendChild(element)
    element.select()

    const succeeded = document.execCommand("copy")

    document.body.removeChild(element)

    if (!succeeded) throw new Error("document.execCommand(copy) failed")
  }

  showCopiedState() {
    if (!this.hasCopyButtonTarget) return

    window.clearTimeout(this.copyResetTimer)
    this.copyButtonTarget.dataset.copied = "true"
    this.copyButtonTarget.setAttribute("aria-label", "In Zwischenablage kopiert")
    this.statusTarget.textContent = "In Zwischenablage kopiert."

    this.copyResetTimer = window.setTimeout(() => {
      delete this.copyButtonTarget.dataset.copied
      this.copyButtonTarget.setAttribute("aria-label", this.defaultCopyButtonLabel)
      this.statusTarget.textContent = ""
    }, 1800)
  }

  showDownloadedState() {
    if (!this.hasDownloadButtonTarget) return

    window.clearTimeout(this.downloadResetTimer)
    this.downloadButtonTarget.dataset.downloaded = "true"
    this.downloadButtonTarget.setAttribute("aria-label", "Payload heruntergeladen")
    this.statusTarget.textContent = "Payload heruntergeladen."

    this.downloadResetTimer = window.setTimeout(() => {
      delete this.downloadButtonTarget.dataset.downloaded
      this.downloadButtonTarget.setAttribute("aria-label", this.defaultDownloadButtonLabel)
      this.statusTarget.textContent = ""
    }, 1800)
  }

  showErrorState(message = "Kopieren fehlgeschlagen.") {
    this.statusTarget.textContent = message
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "status" ]
  static values = {
    copiedLabel: { type: String, default: "Link kopiert" },
    errorLabel: { type: String, default: "Link konnte nicht kopiert werden" },
    text: String,
    title: String,
    url: String
  }

  disconnect() {
    window.clearTimeout(this.resetTimer)
  }

  async share(event) {
    event.preventDefault()
    event.stopPropagation()

    try {
      if (this.canUseNativeShare()) {
        await navigator.share(this.shareData)
        return
      }

      await this.copyUrl()
      this.showStatus(this.copiedLabelValue, "is-confirmed")
    } catch (error) {
      if (error?.name === "AbortError") return

      this.showStatus(this.errorLabelValue, "is-error")
      console.error("Event share failed", error)
    }
  }

  canUseNativeShare() {
    if (!navigator.share) return false
    if (!navigator.canShare) return true

    return navigator.canShare(this.shareData)
  }

  async copyUrl() {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(this.url)
      return
    }

    this.copyUrlWithFallback()
  }

  copyUrlWithFallback() {
    const element = document.createElement("textarea")
    element.value = this.url
    element.setAttribute("readonly", "")
    element.style.position = "absolute"
    element.style.left = "-9999px"

    document.body.appendChild(element)
    element.select()

    const succeeded = document.execCommand("copy")

    document.body.removeChild(element)

    if (!succeeded) throw new Error("document.execCommand(copy) failed")
  }

  showStatus(message, stateClass) {
    window.clearTimeout(this.resetTimer)

    this.buttonTarget.classList.remove("is-confirmed", "is-error")
    this.buttonTarget.classList.add(stateClass)
    this.statusTarget.textContent = message

    this.resetTimer = window.setTimeout(() => {
      this.buttonTarget.classList.remove(stateClass)
      this.statusTarget.textContent = ""
    }, 1800)
  }

  get shareData() {
    const data = {
      title: this.titleValue,
      url: this.url
    }

    if (this.hasTextValue && this.textValue.trim()) {
      data.text = this.textValue
    }

    return data
  }

  get url() {
    return this.hasUrlValue ? this.urlValue : window.location.href
  }
}

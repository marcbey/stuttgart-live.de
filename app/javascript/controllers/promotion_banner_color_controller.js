import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hex", "picker", "eyedropper"]
  static values = { defaultColor: String }

  connect() {
    this.syncPickerToHex()
    this.toggleEyedropper()
  }

  syncFromHex() {
    this.syncPickerToHex()
  }

  normalizeHex() {
    const normalized = this.normalizeValue(this.hexTarget.value)
    this.hexTarget.value = normalized || ""
    this.pickerTarget.value = normalized || this.defaultColorValue
  }

  syncFromPicker() {
    this.hexTarget.value = this.pickerTarget.value.toUpperCase()
  }

  syncPickerToHex() {
    const normalized = this.normalizeValue(this.hexTarget.value)
    this.pickerTarget.value = normalized || this.defaultColorValue
  }

  async pickFromScreen() {
    if (!this.supportsEyedropper()) return

    try {
      const eyeDropper = new window.EyeDropper()
      const { sRGBHex } = await eyeDropper.open()

      this.hexTarget.value = sRGBHex.toUpperCase()
      this.syncPickerToHex()
    } catch (error) {
      if (error?.name == "AbortError") return

      throw error
    }
  }

  toggleEyedropper() {
    if (!this.hasEyedropperTarget) return

    this.eyedropperTarget.hidden = !this.supportsEyedropper()
  }

  normalizeValue(value) {
    const trimmed = value.toString().trim().toUpperCase()
    if (trimmed.length == 0) return null

    const candidate = trimmed.startsWith("#") ? trimmed : `#${trimmed}`
    return /^#[0-9A-F]{6}$/.test(candidate) ? candidate : null
  }

  supportsEyedropper() {
    return typeof window.EyeDropper == "function"
  }
}

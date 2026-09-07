import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [ "input", "signedInput", "removeInput", "removeButton", "preview", "status", "fileName" ]
  static values = { directUploadUrl: String, mediaType: String }

  connect() {
    this.objectUrl = null
    this.defaultFileName = this.hasFileNameTarget ? this.fileNameTarget.textContent.trim() : ""
    this.syncState()
  }

  disconnect() {
    this.revokeObjectUrl()
  }

  select(event) {
    const file = Array.from(event.target.files || [])[0]
    if (!file) return

    const previewUrl = URL.createObjectURL(file)
    this.setObjectUrl(previewUrl)
    this.updatePreview(previewUrl)
    this.setFileName(file.name)
    this.setStatus(`${file.name} wird hochgeladen.`)

    const upload = new DirectUpload(file, this.directUploadUrlValue)
    upload.create((error, blob) => {
      if (error) {
        this.clearSelection({ markForRemoval: false })
        this.setStatus(`Upload fehlgeschlagen: ${error}`)
        return
      }

      this.signedInputTarget.value = blob.signed_id
      this.removeInputTarget.value = "0"
      this.syncState()
      this.setStatus(this.uploadCompleteMessage(file.name))
    })

    event.target.value = ""
  }

  remove() {
    this.clearSelection({ markForRemoval: true })
    this.setStatus(this.mediaTypeValue === "poster" ? "Poster entfernt." : "Video entfernt.")
  }

  clearSelection({ markForRemoval }) {
    this.revokeObjectUrl()
    if (this.hasSignedInputTarget) this.signedInputTarget.value = ""
    if (this.hasRemoveInputTarget) this.removeInputTarget.value = markForRemoval ? "1" : "0"
    this.updatePreview(null)
    this.setFileName(markForRemoval ? "Keine Datei ausgewählt" : this.defaultFileName)
    this.syncState()
  }

  updatePreview(url) {
    if (!this.hasPreviewTarget) return

    if (url) {
      this.previewTarget.src = url
      this.previewTarget.classList.remove("is-hidden")
      return
    }

    this.previewTarget.removeAttribute("src")
    this.previewTarget.classList.add("is-hidden")
  }

  syncState() {
    if (!this.hasRemoveButtonTarget) return

    const hasSignedUpload = this.hasSignedInputTarget && this.signedInputTarget.value.trim() !== ""
    const markedForRemoval = this.hasRemoveInputTarget && this.removeInputTarget.value === "1"
    const hasVisiblePreview = this.hasPreviewTarget && !this.previewTarget.classList.contains("is-hidden")

    this.removeButtonTarget.hidden = !(hasSignedUpload || (hasVisiblePreview && !markedForRemoval))
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }

  uploadCompleteMessage(fileName) {
    if (this.mediaTypeValue !== "video") return `${fileName} wurde hochgeladen.`

    return `${fileName} wurde hochgeladen und wird beim Speichern komprimiert.`
  }

  setFileName(name) {
    if (!this.hasFileNameTarget) return

    this.fileNameTarget.textContent = name || "Keine Datei ausgewählt"
  }

  setObjectUrl(url) {
    this.revokeObjectUrl()
    this.objectUrl = url
  }

  revokeObjectUrl() {
    if (!this.objectUrl) return

    URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }
}

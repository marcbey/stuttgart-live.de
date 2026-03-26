import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [ "input", "signedInput", "removeInput", "removeButton", "previewImage", "placeholder", "previewBox", "status" ]
  static values = { directUploadUrl: String }

  connect() {
    this.objectUrl = null
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
      this.setStatus(`${file.name} wurde hochgeladen.`)
    })

    event.target.value = ""
  }

  remove() {
    this.clearSelection({ markForRemoval: true })
    this.setStatus("Bild aus der aktuellen Auswahl entfernt.")
  }

  clearSelection({ markForRemoval }) {
    this.revokeObjectUrl()
    if (this.hasSignedInputTarget) this.signedInputTarget.value = ""
    if (this.hasRemoveInputTarget) this.removeInputTarget.value = markForRemoval ? "1" : "0"
    this.updatePreview(null)
    this.syncState()
  }

  updatePreview(url) {
    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.src = url || ""
      this.previewImageTarget.classList.toggle("is-hidden", !url)
    }

    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.toggle("is-hidden", Boolean(url))
    }

    if (!url && this.hasPreviewBoxTarget) {
      this.previewBoxTarget.classList.add("is-hidden")
    }
  }

  syncState() {
    if (!this.hasRemoveButtonTarget) return

    const hasSelection = this.hasSignedInputTarget && this.signedInputTarget.value.trim() !== ""
    const markedForRemoval = this.hasRemoveInputTarget && this.removeInputTarget.value === "1"
    const hasVisiblePreview = this.hasPreviewImageTarget && !this.previewImageTarget.classList.contains("is-hidden")

    this.removeButtonTarget.hidden = !(hasSelection || (hasVisiblePreview && !markedForRemoval))
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
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

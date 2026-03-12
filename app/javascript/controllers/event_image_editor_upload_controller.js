import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [ "input", "preview", "status" ]
  static values = {
    directUploadUrl: String,
    signedFieldName: String,
    replaceExisting: { type: Boolean, default: false }
  }

  connect() {
    this.pendingUploads = 0
  }

  select(event) {
    const files = Array.from(event.target.files || [])
    if (files.length === 0) return

    this.uploadFiles(files)
    event.target.value = ""
  }

  beforeSubmit(event) {
    if (this.pendingUploads > 0) {
      event.preventDefault()
      this.setStatus("Bitte warten, bis der Upload abgeschlossen ist.")
      return
    }

    if (this.hasSignedUploads()) {
      this.inputTarget.disabled = true
    }
  }

  removePreview(event) {
    const card = event.currentTarget.closest("[data-upload-signed-id], [data-upload-state='pending']")
    if (!card) return

    card.remove()
    this.setStatus("Bild aus der Auswahl entfernt.")
  }

  uploadFiles(files) {
    if (this.replaceExistingValue) {
      this.previewTarget.innerHTML = ""
    }

    files.forEach((file) => {
      const card = this.buildPendingCard(file)
      this.previewTarget.append(card)
      this.pendingUploads += 1

      const upload = new DirectUpload(file, this.directUploadUrlValue)
      upload.create((error, blob) => {
        this.pendingUploads -= 1

        if (error) {
          card.remove()
          this.setStatus(`Upload fehlgeschlagen: ${error}`)
          return
        }

        card.dataset.uploadSignedId = blob.signed_id
        card.dataset.uploadState = "uploaded"
        const hiddenInput = card.querySelector("input[type='hidden']")
        if (hiddenInput) hiddenInput.value = blob.signed_id
        const statusLabel = card.querySelector("[data-role='upload-status']")
        if (statusLabel) statusLabel.textContent = "Hochgeladen"
        this.setStatus(`${file.name} wurde hochgeladen.`)

        if (this.pendingUploads === 0) {
          this.element.requestSubmit()
        }
      })
    })
  }

  buildPendingCard(file) {
    const card = document.createElement("article")
    card.className = "slider-image-editor-card preuploaded-image-card"
    card.dataset.uploadState = "pending"

    const previewUrl = URL.createObjectURL(file)

    card.innerHTML = `
      <div class="action-cell slider-image-editor-thumb">
        <img src="${previewUrl}" alt="${this.escapeHtml(file.name)}" style="width:56px;height:56px;object-fit:cover;border:1px solid #ddd;">
      </div>
      <div class="slider-image-editor-meta">
        <span class="import-image-editor-label">${this.escapeHtml(file.name)}</span>
        <span class="preuploaded-image-status" data-role="upload-status">Lädt hoch...</span>
        <input type="hidden" name="${this.signedFieldNameValue}" value="">
        <div class="slider-image-meta-actions">
          <button type="button" class="button button-ghost button-compact" data-action="click->event-image-editor-upload#removePreview">Entfernen</button>
        </div>
      </div>
    `

    const image = card.querySelector("img")
    image?.addEventListener("load", () => URL.revokeObjectURL(previewUrl), { once: true })

    return card
  }

  hasSignedUploads() {
    return this.element.querySelector(`input[type='hidden'][name='${this.signedFieldNameValue}']`) !== null
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }

  escapeHtml(value) {
    return value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}

import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [ "heroInput", "sliderInput", "heroPreview", "sliderPreview", "submitButton", "status" ]
  static values = { directUploadUrl: String }

  connect() {
    this.pendingUploads = 0
    this.refreshSubmitState()
  }

  selectHero(event) {
    this.uploadFiles(Array.from(event.target.files || []), { kind: "hero", replaceExisting: true })
    event.target.value = ""
  }

  selectSlider(event) {
    this.uploadFiles(Array.from(event.target.files || []), { kind: "slider", replaceExisting: false })
    event.target.value = ""
  }

  beforeSubmit(event) {
    if (this.pendingUploads > 0) {
      event.preventDefault()
      this.setStatus("Bitte warten, bis alle Bilder hochgeladen sind.")
      return
    }

    if (this.hasSignedUploads("event_image[detail_hero_signed_ids][]") && this.hasHeroInputTarget) {
      this.heroInputTarget.disabled = true
    }

    if (this.hasSignedUploads("event_image[slider_signed_ids][]") && this.hasSliderInputTarget) {
      this.sliderInputTarget.disabled = true
    }
  }

  removePreview(event) {
    const card = event.currentTarget.closest("[data-upload-signed-id]")
    if (!card) return

    card.remove()
    this.setStatus("Bild aus der aktuellen Auswahl entfernt.")
  }

  uploadFiles(files, { kind, replaceExisting }) {
    if (files.length === 0) return

    const previewTarget = this.previewTargetFor(kind)
    if (replaceExisting) previewTarget.innerHTML = ""

    files.forEach((file) => {
      const card = this.buildPendingCard(file, kind)
      previewTarget.append(card)
      this.pendingUploads += 1
      this.refreshSubmitState()

      const upload = new DirectUpload(file, this.directUploadUrlValue)
      upload.create((error, blob) => {
        this.pendingUploads -= 1

        if (error) {
          card.remove()
          this.setStatus(`Upload fehlgeschlagen: ${error}`)
          this.refreshSubmitState()
          return
        }

        card.dataset.uploadSignedId = blob.signed_id
        card.dataset.uploadState = "uploaded"
        const hiddenInput = card.querySelector("input[type='hidden']")
        if (hiddenInput) hiddenInput.value = blob.signed_id
        const statusLabel = card.querySelector("[data-role='upload-status']")
        if (statusLabel) statusLabel.textContent = "Hochgeladen"
        this.setStatus(`${file.name} wurde hochgeladen.`)
        this.refreshSubmitState()
      })
    })
  }

  previewTargetFor(kind) {
    return kind === "hero" ? this.heroPreviewTarget : this.sliderPreviewTarget
  }

  hiddenFieldNameFor(kind) {
    return kind === "hero" ? "event_image[detail_hero_signed_ids][]" : "event_image[slider_signed_ids][]"
  }

  buildPendingCard(file, kind) {
    const card = document.createElement("article")
    card.className = "slider-image-editor-card preuploaded-image-card"
    card.dataset.uploadKind = kind
    card.dataset.uploadState = "pending"

    const previewUrl = URL.createObjectURL(file)

    card.innerHTML = `
      <div class="action-cell slider-image-editor-thumb">
        <img src="${previewUrl}" alt="${this.escapeHtml(file.name)}" style="width:56px;height:56px;object-fit:cover;border:1px solid #ddd;">
      </div>
      <div class="slider-image-editor-meta">
        <span class="import-image-editor-label">${this.escapeHtml(file.name)}</span>
        <span class="preuploaded-image-status" data-role="upload-status">Lädt hoch...</span>
        <input type="hidden" name="${this.hiddenFieldNameFor(kind)}" value="">
        <div class="slider-image-meta-actions">
          <button type="button" class="button button-ghost button-compact" data-action="click->event-image-preupload#removePreview">Entfernen</button>
        </div>
      </div>
    `

    const image = card.querySelector("img")
    image?.addEventListener("load", () => URL.revokeObjectURL(previewUrl), { once: true })

    return card
  }

  refreshSubmitState() {
    if (!this.hasSubmitButtonTarget) return

    this.submitButtonTarget.disabled = this.pendingUploads > 0
    this.submitButtonTarget.setAttribute("aria-busy", this.pendingUploads > 0 ? "true" : "false")
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }

  hasSignedUploads(fieldName) {
    return this.element.querySelector(`input[type='hidden'][name='${fieldName}']`) !== null
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

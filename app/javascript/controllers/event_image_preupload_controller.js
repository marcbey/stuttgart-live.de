import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = [ "heroInput", "heroSignedInput", "heroRemoveButton", "sliderInput", "sliderPreview", "submitButton", "status" ]
  static values = { directUploadUrl: String }

  connect() {
    this.pendingUploads = 0
    this.heroObjectUrl = null
    this.syncHeroRemoveButton()
    this.refreshSubmitState()
  }

  disconnect() {
    this.revokeHeroObjectUrl()
  }

  selectHero(event) {
    this.uploadHeroFile(Array.from(event.target.files || [])[0])
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

  removeHero() {
    this.revokeHeroObjectUrl()
    if (this.hasHeroSignedInputTarget) this.heroSignedInputTarget.value = ""
    this.updateHeroPreview(null)
    this.syncHeroRemoveButton()
    this.setStatus("Eventbild aus der aktuellen Auswahl entfernt.")
  }

  uploadHeroFile(file) {
    if (!file) return

    this.pendingUploads += 1
    this.refreshSubmitState()

    const previewUrl = URL.createObjectURL(file)
    this.setHeroObjectUrl(previewUrl)
    this.updateHeroPreview(previewUrl)
    this.setStatus(`${file.name} wird hochgeladen.`)

    const upload = new DirectUpload(file, this.directUploadUrlValue)
    upload.create((error, blob) => {
      this.pendingUploads -= 1

      if (error) {
        this.removeHero()
        this.setStatus(`Upload fehlgeschlagen: ${error}`)
        this.refreshSubmitState()
        return
      }

      if (this.hasHeroSignedInputTarget) this.heroSignedInputTarget.value = blob.signed_id
      this.syncHeroRemoveButton()
      this.setStatus(`${file.name} wurde hochgeladen.`)
      this.refreshSubmitState()
    })
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
    return this.sliderPreviewTarget
  }

  hiddenFieldNameFor(kind) {
    return "event_image[slider_signed_ids][]"
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

  syncHeroRemoveButton() {
    if (!this.hasHeroRemoveButtonTarget) return

    this.heroRemoveButtonTarget.hidden = !this.hasHeroSelection()
  }

  hasHeroSelection() {
    return this.hasHeroSignedInputTarget && this.heroSignedInputTarget.value.trim() !== ""
  }

  updateHeroPreview(url) {
    const previewImage = this.element.querySelector("[data-event-image-crop-preview-target='previewImage']")
    const placeholder = this.element.querySelector("[data-role='event-image-crop-placeholder']")
    const previewBox = this.element.querySelector("[data-event-image-crop-preview-target='previewBox']")

    if (previewImage) {
      previewImage.src = url || ""
      previewImage.classList.toggle("is-hidden", !url)
    }

    if (placeholder) {
      placeholder.classList.toggle("is-hidden", Boolean(url))
    }

    if (!url && previewBox) {
      previewBox.classList.add("is-hidden")
    }
  }

  setHeroObjectUrl(url) {
    this.revokeHeroObjectUrl()
    this.heroObjectUrl = url
  }

  revokeHeroObjectUrl() {
    if (!this.heroObjectUrl) return

    URL.revokeObjectURL(this.heroObjectUrl)
    this.heroObjectUrl = null
  }

  hasSignedUploads(fieldName) {
    return Array.from(this.element.querySelectorAll(`input[type='hidden'][name='${fieldName}']`)).some((input) => input.value.trim() !== "")
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

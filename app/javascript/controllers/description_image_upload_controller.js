import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static values = { directUploadUrl: String }

  accept(event) {
    const file = event.file

    if (!file || !file.type.startsWith("image/")) {
      event.preventDefault()
    }
  }

  upload(event) {
    event.stopPropagation()

    const attachment = event.attachment
    const file = attachment?.file
    if (!file || !file.type.startsWith("image/")) return

    const upload = new DirectUpload(file, this.directUploadUrlValue)

    upload.create((error, blob) => {
      if (error) {
        attachment.remove()
        window.alert(`Bild-Upload fehlgeschlagen: ${error}`)
        return
      }

      const url = this.blobUrl(blob)
      const attributes = {
        url,
        contentType: blob.content_type,
        filename: blob.filename,
        filesize: blob.byte_size
      }
      const href = this.promptForLinkUrl()

      if (href) attributes.href = href

      attachment.setAttributes(attributes)
    })
  }

  promptForLinkUrl() {
    const value = window.prompt("Bild verlinken? URL eingeben oder leer lassen:")
    if (!value) return null

    const href = this.normalizedLinkUrl(value)
    if (href) return href

    window.alert("Der Bild-Link muss eine gültige http(s)-Adresse oder ein interner Pfad sein.")
    return null
  }

  normalizedLinkUrl(value) {
    const href = value.trim()
    if (!href) return null
    if (href.startsWith("/")) return href

    const url = href.match(/^https?:\/\//i) ? href : `https://${href}`

    try {
      const parsedUrl = new URL(url)
      return ["http:", "https:"].includes(parsedUrl.protocol) ? parsedUrl.toString() : null
    } catch {
      return null
    }
  }

  blobUrl(blob) {
    return `/rails/active_storage/blobs/proxy/${blob.signed_id}/${encodeURIComponent(blob.filename)}`
  }
}

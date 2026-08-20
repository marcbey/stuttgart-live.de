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
      attachment.setAttributes({
        url,
        href: url,
        contentType: blob.content_type,
        filename: blob.filename,
        filesize: blob.byte_size
      })
    })
  }

  blobUrl(blob) {
    return `/rails/active_storage/blobs/proxy/${blob.signed_id}/${encodeURIComponent(blob.filename)}`
  }
}

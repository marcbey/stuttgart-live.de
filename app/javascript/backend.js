import "./javascript_shared/backend_runtime"
import "./controllers/backend_index"

import "trix"
import "@rails/actiontext"

document.addEventListener("trix-initialize", (event) => {
  const editor = event.target
  if (!editor.classList.contains("backend-description-editor")) return

  editor.toolbarElement?.classList.add("backend-description-toolbar")
})

document.addEventListener("trix-file-accept", (event) => {
  if (event.target.classList.contains("backend-description-editor")) {
    event.preventDefault()
  }
})

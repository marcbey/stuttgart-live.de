import "./javascript_shared/backend_runtime"
import "./controllers/backend_index"

import Trix from "trix"
import "@rails/actiontext"

const HEADING_LEVELS = [
  { attribute: "heading2", tagName: "h2", label: "H2", title: "Überschrift 2" },
  { attribute: "heading3", tagName: "h3", label: "H3", title: "Überschrift 3" },
  { attribute: "heading4", tagName: "h4", label: "H4", title: "Überschrift 4" }
]

const configureHeadingAttributes = () => {
  const headingBase = Trix.config.blockAttributes.heading1
  if (!headingBase) return

  HEADING_LEVELS.forEach(({ attribute, tagName }) => {
    Trix.config.blockAttributes[attribute] = {
      ...headingBase,
      tagName
    }
  })
}

const installRichTextHeadingButtons = (editor) => {
  const toolbar = editor.toolbarElement
  if (!toolbar || toolbar.dataset.richTextHeadingsEnhanced === "true") return

  toolbar.dataset.richTextHeadingsEnhanced = "true"
  toolbar.classList.add("backend-rich-text-toolbar")

  const headingButton = toolbar.querySelector("[data-trix-attribute='heading1']")
  const blockTools = headingButton?.closest(".trix-button-group") || toolbar.querySelector(".trix-button-group--block-tools")
  if (!blockTools) return

  HEADING_LEVELS.forEach(({ attribute, label, title }) => {
    const button = document.createElement("button")
    button.type = "button"
    button.className = `trix-button trix-button--icon trix-button--icon-${attribute}`
    button.dataset.trixAttribute = attribute
    button.title = title
    button.tabIndex = -1
    button.textContent = label
    blockTools.insertBefore(button, headingButton)
  })

  headingButton?.remove()
}

configureHeadingAttributes()

document.addEventListener("trix-initialize", (event) => {
  const editor = event.target

  if (editor.classList.contains("blog-rich-text") || editor.classList.contains("backend-description-editor")) {
    installRichTextHeadingButtons(editor)
  }

  if (editor.classList.contains("backend-description-editor")) {
    editor.toolbarElement?.classList.add("backend-description-toolbar")
  }
})

document.addEventListener("trix-file-accept", (event) => {
  if (event.target.classList.contains("backend-description-editor")) {
    event.preventDefault()
  }
})

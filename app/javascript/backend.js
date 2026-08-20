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

const installDescriptionImageButton = (editor) => {
  const toolbar = editor.toolbarElement
  if (!toolbar || toolbar.dataset.descriptionImageButtonEnhanced === "true") return

  const attachButton = toolbar.querySelector(".trix-button--icon-attach")
  const linkButton = toolbar.querySelector("[data-trix-attribute='href']")
  if (!attachButton || !linkButton) return

  toolbar.dataset.descriptionImageButtonEnhanced = "true"
  attachButton.title = "Bild einfügen"
  attachButton.setAttribute("aria-label", "Bild einfügen")
  attachButton.classList.add("backend-description-image-button")
  attachButton.innerHTML = `
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <rect x="3" y="5" width="18" height="14" rx="2"></rect>
      <circle cx="8" cy="10" r="2"></circle>
      <path d="M5 17l5-5 3 3 2-2 4 4"></path>
    </svg>
  `

  const fileTools = attachButton.closest(".trix-button-group")
  const textTools = linkButton.closest(".trix-button-group")

  textTools?.insertBefore(attachButton, linkButton.nextSibling)

  if (fileTools && fileTools !== textTools && fileTools.querySelectorAll(".trix-button").length === 0) {
    fileTools.remove()
  }
}

configureHeadingAttributes()

document.addEventListener("trix-initialize", (event) => {
  const editor = event.target

  if (editor.classList.contains("blog-rich-text") || editor.classList.contains("backend-description-editor")) {
    installRichTextHeadingButtons(editor)
  }

  if (editor.classList.contains("backend-description-editor")) {
    editor.toolbarElement?.classList.add("backend-description-toolbar")
    installDescriptionImageButton(editor)
  }
})

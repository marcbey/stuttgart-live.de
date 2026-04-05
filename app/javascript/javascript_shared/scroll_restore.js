const HISTORY_BACK_SCROLL_RESTORE_KEY = "history-back-link:restore-scroll"

const disableSmoothScrollForHistoryRestore = () => {
  if (window.sessionStorage.getItem(HISTORY_BACK_SCROLL_RESTORE_KEY) !== "true") return

  window.sessionStorage.removeItem(HISTORY_BACK_SCROLL_RESTORE_KEY)

  const root = document.documentElement
  const previousInlineValue = root.style.scrollBehavior

  root.style.scrollBehavior = "auto"

  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (previousInlineValue) {
        root.style.scrollBehavior = previousInlineValue
      } else {
        root.style.removeProperty("scroll-behavior")
      }
    })
  })
}

window.addEventListener("pageshow", disableSmoothScrollForHistoryRestore)
document.addEventListener("turbo:before-render", disableSmoothScrollForHistoryRestore)
document.addEventListener("turbo:load", disableSmoothScrollForHistoryRestore)

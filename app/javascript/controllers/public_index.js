import { application } from "./application"

import ConsentController from "./consent_controller"
import ConsentMediaController from "./consent_media_controller"
import FlashController from "./flash_controller"
import HistoryBackLinkController from "./history_back_link_controller"
import MobileNavController from "./mobile_nav_controller"
import NavOffsetController from "./nav_offset_controller"
import PublicSearchController from "./public_search_controller"
import SavedEventToggleController from "./saved_event_toggle_controller"
import SavedEventsNavController from "./saved_events_nav_controller"
import SavedEventsLaneController from "./saved_events_lane_controller"
import ScrollTopController from "./scroll_top_controller"
import ShareEventController from "./share_event_controller"

const registeredControllers = new Set()

const registerController = (identifier, controller) => {
  if (registeredControllers.has(identifier)) return

  application.register(identifier, controller)
  registeredControllers.add(identifier)
}

registerController("consent", ConsentController)
registerController("consent-media", ConsentMediaController)
registerController("flash", FlashController)
registerController("history-back-link", HistoryBackLinkController)
registerController("mobile-nav", MobileNavController)
registerController("nav-offset", NavOffsetController)
registerController("public-search", PublicSearchController)
registerController("saved-event-toggle", SavedEventToggleController)
registerController("saved-events-nav", SavedEventsNavController)
registerController("saved-events-lane", SavedEventsLaneController)
registerController("scroll-top", ScrollTopController)
registerController("share-event", ShareEventController)

const lazyControllers = {
  "backend-nav-menu": () => import("./backend_nav_menu_controller"),
  "event-series-calendar": () => import("./event_series_calendar_controller"),
  "hero-rotator": () => import("./hero_rotator_controller"),
  "highlights-slider": () => import("./highlights_slider_controller"),
  "homepage-lane": () => import("./homepage_lane_controller"),
  "infinite-scroll": () => import("./infinite_scroll_controller"),
  "lane-page": () => import("./lane_page_controller"),
  "lightbox": () => import("./lightbox_controller"),
  "partner-strip": () => import("./partner_strip_controller"),
  "section-view": () => import("./section_view_controller")
}

const controllerNamesInDocument = () => {
  const names = new Set()

  document.querySelectorAll("[data-controller]").forEach((element) => {
    element.dataset.controller.split(/\s+/).forEach((name) => {
      if (name) names.add(name)
    })
  })

  return names
}

const loadLazyControllers = () => {
  const controllerNames = controllerNamesInDocument()

  Object.entries(lazyControllers).forEach(([identifier, loadController]) => {
    if (registeredControllers.has(identifier) || !controllerNames.has(identifier)) return

    loadController().then((module) => registerController(identifier, module.default))
  })
}

loadLazyControllers()
document.addEventListener("DOMContentLoaded", loadLazyControllers)
document.addEventListener("turbo:load", loadLazyControllers)

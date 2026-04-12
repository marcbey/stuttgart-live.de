import { application } from "./application"

import BackendNavMenuController from "./backend_nav_menu_controller"
application.register("backend-nav-menu", BackendNavMenuController)

import ConsentController from "./consent_controller"
application.register("consent", ConsentController)

import ConsentMediaController from "./consent_media_controller"
application.register("consent-media", ConsentMediaController)

import FlashController from "./flash_controller"
application.register("flash", FlashController)

import HeroRotatorController from "./hero_rotator_controller"
application.register("hero-rotator", HeroRotatorController)

import HighlightsSliderController from "./highlights_slider_controller"
application.register("highlights-slider", HighlightsSliderController)

import HistoryBackLinkController from "./history_back_link_controller"
application.register("history-back-link", HistoryBackLinkController)

import InfiniteScrollController from "./infinite_scroll_controller"
application.register("infinite-scroll", InfiniteScrollController)

import LightboxController from "./lightbox_controller"
application.register("lightbox", LightboxController)

import MobileNavController from "./mobile_nav_controller"
application.register("mobile-nav", MobileNavController)

import NavOffsetController from "./nav_offset_controller"
application.register("nav-offset", NavOffsetController)

import PartnerStripController from "./partner_strip_controller"
application.register("partner-strip", PartnerStripController)

import PublicSearchController from "./public_search_controller"
application.register("public-search", PublicSearchController)

import SavedEventToggleController from "./saved_event_toggle_controller"
application.register("saved-event-toggle", SavedEventToggleController)

import SavedEventsNavController from "./saved_events_nav_controller"
application.register("saved-events-nav", SavedEventsNavController)

import SavedEventsLaneController from "./saved_events_lane_controller"
application.register("saved-events-lane", SavedEventsLaneController)

import ScrollTopController from "./scroll_top_controller"
application.register("scroll-top", ScrollTopController)

import SectionViewController from "./section_view_controller"
application.register("section-view", SectionViewController)

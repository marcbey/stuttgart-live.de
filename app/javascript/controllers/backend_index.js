import { application } from "./application"

import AutosaveController from "./autosave_controller"
application.register("autosave", AutosaveController)

import BackendNavMenuController from "./backend_nav_menu_controller"
application.register("backend-nav-menu", BackendNavMenuController)

import BlogPostImagePreuploadController from "./blog_post_image_preupload_controller"
application.register("blog-post-image-preupload", BlogPostImagePreuploadController)

import BulkSelectController from "./bulk_select_controller"
application.register("bulk-select", BulkSelectController)

import ClipboardController from "./clipboard_controller"
application.register("clipboard", ClipboardController)

import EditorInboxController from "./editor_inbox_controller"
application.register("editor-inbox", EditorInboxController)

import EventEditorTabsController from "./event_editor_tabs_controller"
application.register("event-editor-tabs", EventEditorTabsController)

import EventImageCropPreviewController from "./event_image_crop_preview_controller"
application.register("event-image-crop-preview", EventImageCropPreviewController)

import EventImageEditorUploadController from "./event_image_editor_upload_controller"
application.register("event-image-editor-upload", EventImageEditorUploadController)

import EventImagePreuploadController from "./event_image_preupload_controller"
application.register("event-image-preupload", EventImagePreuploadController)

import FlashController from "./flash_controller"
application.register("flash", FlashController)

import KeyboardShortcutsController from "./keyboard_shortcuts_controller"
application.register("keyboard-shortcuts", KeyboardShortcutsController)

import LiveSearchController from "./live_search_controller"
application.register("live-search", LiveSearchController)

import MergeChangeFilterController from "./merge_change_filter_controller"
application.register("merge-change-filter", MergeChangeFilterController)

import MobileNavController from "./mobile_nav_controller"
application.register("mobile-nav", MobileNavController)

import NavOffsetController from "./nav_offset_controller"
application.register("nav-offset", NavOffsetController)

import NextEventController from "./next_event_controller"
application.register("next-event", NextEventController)

import PromotionBannerColorController from "./promotion_banner_color_controller"
application.register("promotion-banner-color", PromotionBannerColorController)

import PromotionBannerImagePreuploadController from "./promotion_banner_image_preupload_controller"
application.register("promotion-banner-image-preupload", PromotionBannerImagePreuploadController)

import ScrollTopController from "./scroll_top_controller"
application.register("scroll-top", ScrollTopController)

import SettingsSortableController from "./settings_sortable_controller"
application.register("settings-sortable", SettingsSortableController)

import SettingsTabsController from "./settings_tabs_controller"
application.register("settings-tabs", SettingsTabsController)

import VenueAutocompleteController from "./venue_autocomplete_controller"
application.register("venue-autocomplete", VenueAutocompleteController)

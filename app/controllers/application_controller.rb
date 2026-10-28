class ApplicationController < ActionController::Base
  include Authentication
  # Public content must remain accessible on older devices, including iPhone 8.
  allow_browser versions: :modern, unless: -> { controller_path.start_with?("public/") }

  before_action :set_header_browse_state

  private

  def set_header_browse_state
    return if controller_path.start_with?("backend/")
    return unless header_search_enabled?

    @header_browse_state = Public::Events::BrowseState.new(params)
  end

  def header_search_enabled?
    controller_path.start_with?("public/")
  end
end

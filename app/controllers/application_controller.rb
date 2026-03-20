class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_header_browse_state

  private

  def set_header_browse_state
    return if controller_path.start_with?("backend/")
    return unless header_search_enabled?

    @header_browse_state = Public::Events::BrowseState.new(params)
  end

  def header_search_enabled?
    return true if controller_path == "public/events" && action_name == "index"
    return true if controller_path == "public/news" && action_name == "index"

    controller_path == "public/pages" && %w[contact imprint terms accessibility].include?(action_name)
  end
end

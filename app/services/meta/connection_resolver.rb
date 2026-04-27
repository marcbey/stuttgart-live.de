module Meta
  class ConnectionResolver
    def initialize(scope: SocialConnection.includes(:social_connection_targets), platform: nil)
      @scope = scope
      @platform = platform.to_s.strip.presence
    end

    def connection
      return connection_for(platform) if platform.present?

      instagram_connection || facebook_connection
    end

    def connection_for(platform)
      scope.find_by(provider: "meta", platform: platform.to_s)
    end

    def connection_for!(platform)
      connection_for(platform) || raise(Error, "Meta-Verbindung für #{platform_label(platform)} ist nicht eingerichtet.")
    end

    def instagram_connection
      connection_for("instagram")
    end

    def facebook_connection
      connection_for("facebook")
    end

    def connection!
      connection || raise(Error, "Meta-Verbindung ist nicht eingerichtet.")
    end

    def selected_facebook_page_target!
      target = connection_for!("facebook")&.selected_facebook_page_target
      raise Error, "Es ist keine Facebook-Seite für Meta ausgewählt." if target.blank?

      target
    end

    def selected_instagram_target!
      target = connection_for!("instagram")&.selected_instagram_target
      raise Error, "Es ist kein Instagram-Professional-Account für das Publishing verbunden." if target.blank?

      target
    end

    private

    attr_reader :platform, :scope

    def platform_label(platform)
      case platform.to_s
      when "facebook" then "Facebook"
      when "instagram" then "Instagram"
      else "Meta"
      end
    end
  end
end

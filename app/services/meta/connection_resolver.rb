module Meta
  class ConnectionResolver
    def initialize(scope: SocialConnection.includes(:social_connection_targets))
      @scope = scope
    end

    def connection
      scope.find_by(provider: "meta")
    end

    def connection!
      connection || raise(Error, "Meta-Verbindung ist nicht eingerichtet.")
    end

    def selected_facebook_page_target!
      target = connection!&.selected_facebook_page_target
      raise Error, "Es ist keine Facebook-Seite für Meta ausgewählt." if target.blank?

      target
    end

    def selected_instagram_target!
      target = connection!&.selected_instagram_target
      raise Error, "Es ist kein Instagram-Professional-Account für das Publishing verbunden." if target.blank?

      target
    end

    private

    attr_reader :scope
  end
end

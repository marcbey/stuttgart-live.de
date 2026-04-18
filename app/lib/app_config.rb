module AppConfig
  class << self
    def eventim_user
      fetch(:eventim, :user, env: "EVENTIM_USER")
    end

    def eventim_pass
      fetch(:eventim, :pass, env: "EVENTIM_PASS")
    end

    def eventim_feed_key
      fetch(:eventim, :feed_key, env: "EVENTIM_FEED_KEY")
    end

    def eventim_feed_url
      return if eventim_user.blank? || eventim_pass.blank? || eventim_feed_key.blank?

      "https://#{eventim_user}:#{eventim_pass}@pft.eventim.com/serve/#{eventim_feed_key}"
    end

    def reservix_api_key
      fetch(:reservix, :api_key, env: "RESERVIX_API_KEY")
    end

    def reservix_events_api
      fetch(:reservix, :events_api, env: "RESERVIX_EVENTS_API")
    end

    def serpapi_api_key
      fetch(:serpapi, :api_key, env: "SERPAPI_API_KEY")
    end

    def openwebninja_api_key
      fetch(:openwebninja, :api_key, env: "OPENWEBNINJA_API_KEY")
    end

    def easyticket_events_api
      fetch(:easyticket, :events_api, env: "EASYTICKET_EVENTS_API")
    end

    def easyticket_event_detail_api
      fetch(:easyticket, :event_detail_api, env: "EASYTICKET_EVENT_DETAIL_API")
    end

    def easyticket_partner_shop_id
      fetch(:easyticket, :partner_shop_id, env: "EASYTICKET_PARTNER_SHOP_ID")
    end

    def easyticket_ticket_link_event_base_url
      fetch(:easyticket, :ticket_link_event_base_url, env: "EASYTICKET_TICKET_LINK_EVENT_BASE_URL")
    end

    def mailchimp_api_key
      fetch(:mailchimp, :api_key, env: "MAILCHIMP_API_KEY")
    end

    def mailchimp_list_id
      fetch(:mailchimp, :list_id, env: "MAILCHIMP_LIST_ID") ||
        fetch(:mailchimp, :audience_id, env: "MAILCHIMP_AUDIENCE_ID")
    end

    def mailchimp_server_prefix
      fetch(:mailchimp, :server_prefix, env: "MAILCHIMP_SERVER_PREFIX")
    end

    def smtp_address
      fetch(:smtp, :address, env: "SMTP_ADDRESS")
    end

    def smtp_port
      fetch(:smtp, :port, env: "SMTP_PORT")
    end

    def smtp_user_name
      fetch(:smtp, :user_name, env: "SMTP_USERNAME") ||
        fetch(:smtp, :username, env: "SMTP_USERNAME")
    end

    def smtp_password
      fetch(:smtp, :password, env: "SMTP_PASSWORD")
    end

    def smtp_domain
      fetch(:smtp, :domain, env: "SMTP_DOMAIN")
    end

    def smtp_authentication
      fetch(:smtp, :authentication, env: "SMTP_AUTHENTICATION")
    end

    def smtp_enable_starttls_auto
      fetch(:smtp, :enable_starttls_auto, env: "SMTP_ENABLE_STARTTLS_AUTO")
    end

    def meta_app_id
      fetch(:meta, :app_id, env: "META_APP_ID")
    end

    def meta_app_secret
      fetch(:meta, :app_secret, env: "META_APP_SECRET")
    end

    def meta_instagram_app_id
      fetch(:meta, :instagram_app_id, env: "META_INSTAGRAM_APP_ID") || meta_app_id
    end

    def meta_instagram_app_secret
      fetch(:meta, :instagram_app_secret, env: "META_INSTAGRAM_APP_SECRET") || meta_app_secret
    end

    def meta_instagram_redirect_uri
      fetch(:meta, :instagram_redirect_uri, env: "META_INSTAGRAM_REDIRECT_URI")
    end

    def meta_facebook_page_id
      fetch(:meta, :facebook_page_id, env: "META_FACEBOOK_PAGE_ID")
    end

    def meta_facebook_page_access_token
      fetch(:meta, :facebook_page_access_token, env: "META_FACEBOOK_PAGE_ACCESS_TOKEN")
    end

    def meta_instagram_business_account_id
      fetch(:meta, :instagram_business_account_id, env: "META_INSTAGRAM_BUSINESS_ACCOUNT_ID")
    end

    private

    def fetch(*keys, env:)
      configured_value(Rails.application.credentials.dig(*keys)) ||
        configured_value(ENV[env])
    end

    def configured_value(value)
      return nil if value.nil?
      return value.strip.presence if value.is_a?(String)

      value
    end
  end
end

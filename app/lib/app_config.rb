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

    def mailjet_api_key
      mailjet_credential(:api_key, :mailjet_api_key) ||
        configured_value(ENV["MAILJET_API_KEY"]) ||
        configured_value(ENV["MJ_APIKEY_PUBLIC"])
    end

    def mailjet_secret_key
      mailjet_credential(:secret_key, :mailjet_secret_key) ||
        configured_value(ENV["MAILJET_SECRET_KEY"]) ||
        configured_value(ENV["MJ_APIKEY_PRIVATE"])
    end

    def mailjet_list_id
      mailjet_credential(:list_id, :mailjet_list_id) ||
        configured_value(ENV["MAILJET_LIST_ID"])
    end

    def mailjet_api_endpoint
      mailjet_credential(:api_endpoint, :mailjet_api_endpoint) ||
        configured_value(ENV["MAILJET_API_ENDPOINT"])
    end

    def mailjet_sender
      mailjet_credential(:sender, :mailjet_sender) ||
        configured_value(ENV["MAILJET_SENDER"])
    end

    def newsletter_final_send_enabled?
      ActiveModel::Type::Boolean.new.cast(
        fetch(:newsletter, :final_send_enabled, env: "NEWSLETTER_FINAL_SEND_ENABLED")
      )
    end

    def newsletter_test_list_send_enabled?
      value = fetch(:newsletter, :test_list_send_enabled, env: "NEWSLETTER_TEST_LIST_SEND_ENABLED")
      return Rails.env.development? || Rails.env.test? if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
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

    def mailer_from
      fetch(:mailer, :from, env: "MAILER_FROM")
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

    private

    def fetch(*keys, env:)
      configured_value(Rails.application.credentials.dig(*keys)) ||
        configured_value(ENV[env])
    end

    def mailjet_credential(*keys)
      keys.lazy
        .map { |key| configured_value(Rails.application.credentials.dig(:mailjet, key)) }
        .find(&:present?)
    end

    def configured_value(value)
      return nil if value.nil?
      return value.strip.presence if value.is_a?(String)

      value
    end
  end
end

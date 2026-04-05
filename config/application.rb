require_relative "boot"
require_relative "../app/lib/production_server_config"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StuttgartLiveDe
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Berlin"
    config.i18n.default_locale = :de
    config.exceptions_app = routes
    config.active_storage.variant_processor =
      begin
        require "vips"
        :vips
      rescue LoadError
        :mini_magick
      end
    config.x.google_analytics_measurement_id = "G-103580617"
    config.x.mailer_from = "Stuttgart Live <no-reply@stuttgart-live.schopp3r.de>"
    config.x.openai.llm_enrichment_model = ENV["OPENAI_LLM_ENRICHMENT_MODEL"].to_s.strip.presence || "gpt-5.1"
    config.x.media_proxy.enabled = ProductionServerConfig.media_proxy_enabled?
    config.x.media_proxy.secret = ProductionServerConfig.media_proxy_secret
    config.x.media_proxy.ttl = ProductionServerConfig.media_proxy_ttl
    config.active_storage.content_types_to_serve_as_binary -= [ "image/svg+xml" ]
    config.active_storage.content_types_allowed_inline += [ "image/svg+xml" ]
    # config.eager_load_paths << Rails.root.join("extras")
  end
end

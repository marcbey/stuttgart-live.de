module Meta
  module PublicAssetUrl
    module_function

    def url_for(record)
      return if record.blank?

      options = url_options
      return if options[:host].blank?

      PublicMediaUrl.url_for(record, url_options: options) ||
        Rails.application.routes.url_helpers.rails_storage_proxy_url(record, **options)
    end

    def url_options
      @url_options ||= begin
        options = Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
        options[:host] ||= HetznerDeployConfig.app_host_if_present
        options[:protocol] ||= options[:host].to_s.include?("localhost") ? "http" : "https"
        options.compact
      end
    end
  end
end

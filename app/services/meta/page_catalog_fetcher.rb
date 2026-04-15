module Meta
  class PageCatalogFetcher
    API_VERSION = "v25.0".freeze
    PAGE_FIELDS = "id,name,access_token,instagram_business_account{id,username}".freeze

    PageAccount = Data.define(:page_id, :page_name, :page_access_token, :instagram_account_id, :instagram_username)

    def initialize(http_client: HttpClient.new)
      @http_client = http_client
    end

    def call(user_access_token:)
      payload = http_client.get_json!(
        "https://graph.facebook.com/#{API_VERSION}/me/accounts",
        params: {
          fields: PAGE_FIELDS,
          access_token: user_access_token
        }
      )

      Array(payload["data"]).filter_map do |item|
        page_id = item["id"].to_s.strip.presence
        next if page_id.blank?

        instagram_account = item["instagram_business_account"] || {}

        PageAccount.new(
          page_id:,
          page_name: item["name"].to_s.strip.presence,
          page_access_token: item["access_token"].to_s.strip.presence,
          instagram_account_id: instagram_account["id"].to_s.strip.presence,
          instagram_username: instagram_account["username"].to_s.strip.presence
        )
      end
    end

    private

    attr_reader :http_client
  end
end

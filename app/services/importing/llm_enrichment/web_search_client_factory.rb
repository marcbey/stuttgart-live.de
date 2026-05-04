module Importing
  module LlmEnrichment
    class WebSearchClientFactory
      def self.build(provider: AppSetting.llm_enrichment_web_search_provider)
        case provider.to_s
        when "openwebninja"
          CachingWebSearchClient.new(provider: "openwebninja", client: OpenWebNinjaWebSearchClient.new)
        else
          CachingWebSearchClient.new(provider: "serpapi", client: SerpApiClient.new)
        end
      end
    end
  end
end

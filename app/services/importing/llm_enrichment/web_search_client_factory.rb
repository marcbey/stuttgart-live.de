module Importing
  module LlmEnrichment
    class WebSearchClientFactory
      def self.build(provider: AppSetting.llm_enrichment_web_search_provider, api_call_recorder: nil)
        case provider.to_s
        when "openwebninja"
          CachingWebSearchClient.new(
            provider: "openwebninja",
            client: OpenWebNinjaWebSearchClient.new,
            api_call_recorder: api_call_recorder
          )
        else
          CachingWebSearchClient.new(
            provider: "serpapi",
            client: SerpApiClient.new,
            api_call_recorder: api_call_recorder
          )
        end
      end
    end
  end
end

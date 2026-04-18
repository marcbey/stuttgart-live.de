module Importing
  module LlmEnrichment
    module WebSearchResponse
      OrganicResult = Data.define(:position, :link, :title, :snippet)
      SearchResult = Data.define(:search_id, :organic_results)
    end
  end
end

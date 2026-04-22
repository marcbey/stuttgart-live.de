module Importing
  module LlmEnrichment
    module WebSearchResponse
      OrganicResult = Data.define(
        :position,
        :link,
        :title,
        :displayed_link,
        :snippet,
        :source,
        :about_source_description,
        :languages,
        :regions
      )
      SearchResult = Data.define(:search_id, :organic_results)
    end
  end
end

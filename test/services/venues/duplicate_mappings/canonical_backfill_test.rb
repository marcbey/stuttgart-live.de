require "test_helper"

module Venues
  module DuplicateMappings
    class CanonicalBackfillTest < ActiveSupport::TestCase
      test "creates missing canonical venue from mapping" do
        CanonicalBackfill.call(mappings: mappings_for("Alias Venue" => "Canonical Venue"))

        canonical = Venue.find_by_match_name("Canonical Venue")
        assert_predicate canonical, :present?
        assert_equal "Canonical Venue", canonical.name
      end

      test "does not duplicate existing canonical venue" do
        existing = Venue.create!(name: "Canonical Venue")

        assert_no_difference -> { Venue.where("LOWER(name) = ?", "canonical venue").count } do
          CanonicalBackfill.call(mappings: mappings_for("Alias Venue" => "Canonical Venue"))
        end

        assert_equal existing, Venue.find_by_match_name("Canonical Venue")
      end

      test "copies metadata from best existing alias venue" do
        sparse_alias = Venue.create!(name: "Sparse Alias", description: "Nur Beschreibung")
        best_alias = Venue.create!(
          name: "Rich Alias",
          description: "Beste Beschreibung",
          external_url: "https://rich.example",
          address: "Richstraße 1, 70173 Stuttgart"
        )
        best_alias.logo.attach(create_uploaded_blob(filename: "rich-alias.png"))
        create_event_for(venue: sparse_alias, title: "Sparse Event")
        create_event_for(venue: best_alias, title: "Rich Event")

        CanonicalBackfill.call(
          mappings: mappings_for(
            "Sparse Alias" => "Canonical Venue",
            "Rich Alias" => "Canonical Venue"
          )
        )

        canonical = Venue.find_by_match_name("Canonical Venue")
        assert_equal "Beste Beschreibung", canonical.description
        assert_equal "https://rich.example", canonical.external_url
        assert_equal "Richstraße 1, 70173 Stuttgart", canonical.address
        assert canonical.logo.attached?
        assert_equal best_alias.logo.blob, canonical.logo.blob
      end

      test "uses event count as tie breaker for best alias venue" do
        low_event_alias = Venue.create!(name: "Low Event Alias", description: "Low")
        high_event_alias = Venue.create!(name: "High Event Alias", description: "High")
        create_event_for(venue: high_event_alias, title: "High Event One")
        create_event_for(venue: high_event_alias, title: "High Event Two")
        create_event_for(venue: low_event_alias, title: "Low Event")

        CanonicalBackfill.call(
          mappings: mappings_for(
            "Low Event Alias" => "Canonical Venue",
            "High Event Alias" => "Canonical Venue"
          )
        )

        assert_equal "High", Venue.find_by_match_name("Canonical Venue").description
      end

      test "creates canonical venue without metadata when alias venue does not exist" do
        CanonicalBackfill.call(mappings: mappings_for("Missing Alias" => "Canonical Venue"))

        canonical = Venue.find_by_match_name("Canonical Venue")
        assert_equal "Canonical Venue", canonical.name
        assert_nil canonical.description
        assert_nil canonical.external_url
        assert_nil canonical.address
        assert_not canonical.logo.attached?
      end

      test "creates only one canonical venue for multiple aliases with the same target" do
        CanonicalBackfill.call(
          mappings: mappings_for(
            "Alias One" => "Canonical Venue",
            "Alias Two" => "Canonical Venue"
          )
        )

        assert_equal 1, Venue.select { |venue| Venue.match_key(venue.name) == "canonical venue" }.size
      end

      private

      def mappings_for(mapping)
        mapping.map do |alias_name, canonical_name|
          {
            "alias" => alias_name,
            "canonical" => canonical_name,
            "alias_key" => Venue.match_key(alias_name),
            "canonical_key" => Venue.match_key(canonical_name)
          }
        end
      end

      def create_event_for(venue:, title:)
        Event.create!(
          artist_name: "#{title} Artist",
          title:,
          start_at: 1.day.from_now.change(usec: 0),
          venue_record: venue,
          city: "Stuttgart",
          status: "needs_review"
        )
      end
    end
  end
end

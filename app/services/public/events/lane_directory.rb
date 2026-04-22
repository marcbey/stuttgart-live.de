module Public
  module Events
    class LaneDirectory
      Lane = Data.define(:key, :title, :header_variant, :public_path, :group, :featured, :home_visible)

      FIXED_LANES = {
        "highlights" => {
          title: "Unsere Highlights",
          header_variant: :highlights,
          public_path: "/highlights",
          featured: true
        },
        "russ_live" => {
          title: "RUSS Live",
          header_variant: :highlights,
          public_path: "/russ-live",
          featured: false,
          home_visible: false
        },
        "all_stuttgart" => {
          title: "alles aus stuttgart",
          header_variant: :editorial,
          public_path: "/alles-aus-stuttgart",
          featured: false
        },
        "tagestipp" => {
          title: "Tagestipp",
          header_variant: :tagestipp,
          public_path: "/tagestipp",
          featured: false
        }
      }.freeze

      FIXED_PUBLIC_SLUGS = FIXED_LANES.values.map { |lane| lane.fetch(:public_path).delete_prefix("/") }.freeze

      class << self
        def all_stuttgart
          fixed("all_stuttgart")
        end

        def fixed(key)
          attributes = FIXED_LANES[key.to_s]
          return if attributes.blank?

          Lane.new(
            key: key.to_s,
            title: attributes.fetch(:title),
            header_variant: attributes.fetch(:header_variant),
            public_path: attributes.fetch(:public_path),
            group: nil,
            featured: attributes.fetch(:featured),
            home_visible: attributes.fetch(:home_visible, true)
          )
        end

        def genre(slug, snapshot: LlmGenreGrouping::Lookup.selected_snapshot)
          normalized_slug = normalize_slug(slug)
          return if normalized_slug.blank?

          group = snapshot&.groups&.find { |entry| entry.slug == normalized_slug }
          return if group.blank?

          Lane.new(
            key: "genre",
            title: group.name,
            header_variant: :genre,
            public_path: routeable_genre_slug?(normalized_slug, snapshot: snapshot) ? "/#{normalized_slug}" : nil,
            group: group,
            featured: false,
            home_visible: snapshot_home_lane_slugs(snapshot).include?(normalized_slug)
          )
        end

        def highlights
          fixed("highlights")
        end

        def russ_live
          fixed("russ_live")
        end

        def public_path_for_genre_slug(slug, snapshot: LlmGenreGrouping::Lookup.selected_snapshot)
          genre(slug, snapshot: snapshot)&.public_path
        end

        def resolve(identifier, snapshot: LlmGenreGrouping::Lookup.selected_snapshot)
          case identifier.to_s
          when "highlights" then highlights
          when "russ_live" then russ_live
          when "all_stuttgart" then all_stuttgart
          when "tagestipp" then tagestipp
          else genre(identifier, snapshot: snapshot)
          end
        end

        def routeable_genre_slug?(slug, snapshot: LlmGenreGrouping::Lookup.selected_snapshot)
          normalized_slug = normalize_slug(slug)
          return false if normalized_slug.blank?
          return false if reserved_public_slugs.include?(normalized_slug)
          return false unless snapshot&.groups&.any? { |group| group.slug == normalized_slug }
          return false if StaticPage.exists?(slug: normalized_slug)

          true
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
          false
        end

        def tagestipp
          fixed("tagestipp")
        end

        private

        def normalize_slug(slug)
          slug.to_s.strip.parameterize.presence
        end

        def reserved_public_slugs
          @reserved_public_slugs ||= (StaticPage::RESERVED_SLUGS + FIXED_PUBLIC_SLUGS).uniq
        end

        def snapshot_home_lane_slugs(snapshot)
          Array(snapshot&.homepage_genre_lane_configuration&.lane_slugs)
        end
      end
    end
  end
end

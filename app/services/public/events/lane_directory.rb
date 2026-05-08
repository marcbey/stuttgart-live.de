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
            home_visible: true
          )
        end

        def genre(slug)
          normalized_slug = normalize_slug(slug)
          return if normalized_slug.blank?

          group = Genre.find_by(slug: normalized_slug)
          return if group.blank?

          Lane.new(
            key: "genre",
            title: group.name,
            header_variant: :genre,
            public_path: routeable_genre_slug?(normalized_slug) ? "/#{normalized_slug}" : nil,
            group: group,
            featured: false,
            home_visible: AppSetting.homepage_genre_lane_slugs.include?(normalized_slug)
          )
        end

        def highlights
          fixed("highlights")
        end

        def public_path_for_genre_slug(slug)
          genre(slug)&.public_path
        end

        def public_paths_for_genre_slugs(slugs)
          normalized_slugs = Array(slugs).filter_map { |slug| normalize_slug(slug) }.uniq
          return {} if normalized_slugs.empty?

          routeable_slugs(normalized_slugs).index_with { |slug| "/#{slug}" }
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
          {}
        end

        def resolve(identifier)
          case identifier.to_s
          when "highlights" then highlights
          when "all_stuttgart" then all_stuttgart
          when "tagestipp" then tagestipp
          else genre(identifier)
          end
        end

        def routeable_genre_slug?(slug)
          normalized_slug = normalize_slug(slug)
          return false if normalized_slug.blank?

          routeable_slugs([ normalized_slug ]).include?(normalized_slug)
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

        def routeable_slugs(slugs)
          candidates = Array(slugs).filter_map { |slug| normalize_slug(slug) }.uniq
          candidates -= reserved_public_slugs
          return [] if candidates.empty?

          genre_slugs = Genre.where(slug: candidates).pluck(:slug)
          static_page_slugs = StaticPage.where(slug: genre_slugs).pluck(:slug)

          genre_slugs - static_page_slugs
        end
      end
    end
  end
end

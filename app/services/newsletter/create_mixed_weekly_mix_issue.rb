module Newsletter
  class CreateMixedWeeklyMixIssue
    ITEM_LIMIT = 10

    def self.call(user: nil, today: Time.zone.today)
      new(user:, today:).call
    end

    def initialize(user:, today:)
      @user = user
      @today = today
    end

    def call
      issue = NewsletterIssue.create!(
        title: draft_title,
        subject: "Dein Stuttgart Live Wochenmix",
        preheader: "Zehn ausgewählte Events aus unserem Wochenmix.",
        intro: default_intro,
        layout_variant: "mixed_weekly_mix",
        team_tip_profile_key: "sarah-sandner",
        team_tip_text: default_team_tip_text,
        created_by: user
      )

      selected_events.each.with_index(1) do |event, position|
        issue.newsletter_issue_items.create!(
          item: event,
          position:,
          section_key: header_group_for(event)&.slug,
          cta_label: "Zum Event"
        )
      end

      issue
    end

    private

    attr_reader :user, :today

    def draft_title
      "Wochenmix KW #{today.cweek}/#{today.cwyear} #{Time.current.strftime('%d.%m.%Y %H:%M')}"
    end

    def selected_events
      candidates = Event
        .published_live
        .joins(:genres)
        .includes(:event_series, :genres)
        .where(genres: { id: Newsletter::HeaderGenreGroups.all.map { |group| group.genre.id } })
        .where("events.start_at >= ?", today.beginning_of_day)
        .reorder(Arel.sql(Event.search_priority_order_sql), :start_at, :id)
        .limit(ITEM_LIMIT * 25)
        .to_a
        .uniq(&:id)

      Public::Events::SeriesRepresentativeSelector.call(candidates).first(ITEM_LIMIT)
    end

    def header_group_for(event)
      genre_slugs = event.genres.map(&:slug)
      Newsletter::HeaderGenreGroups.all.find { |group| genre_slugs.include?(group.slug) }
    end

    def default_intro
      <<~TEXT.strip
        unsere Event-Highlights der Woche, passend zu deinen Interessen und handverlesen statt wahllos zusammengestellt.
        Regelmäßig frisch. Persönlich für dich ♥
      TEXT
    end

    def default_team_tip_text
      <<~TEXT.squish
        Mein ganz persönlicher Tipp für euch: Lorem ipsum dolor sit amet,
        consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt
        ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos
        et accusam et justo duo dolores et ea rebum.
      TEXT
    end
  end
end

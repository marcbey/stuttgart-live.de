require "set"

module Newsletter
  class CreateWeeklyGenreMixIssue
    ITEMS_PER_GENRE = 6

    def self.call(user: nil, today: Time.zone.today, items_per_genre: ITEMS_PER_GENRE)
      new(user:, today:, items_per_genre:).call
    end

    def initialize(user:, today:, items_per_genre:)
      @user = user
      @today = today
      @items_per_genre = items_per_genre
      @selected_event_ids = Set.new
      @selected_series_keys = Set.new
    end

    def call
      issue = NewsletterIssue.create!(
        title: draft_title,
        subject: "Dein Stuttgart Live Wochenmix",
        jump_menu_title: "Für was interessierst du dich? Spring hinein ins Vergnügen :-)",
        preheader: "Highlights und kommende Events aus allen Hauptgenres.",
        intro: default_intro,
        layout_variant: "genre_weekly_mix",
        team_tip_profile_key: "sarah-sandner",
        team_tip_text: default_team_tip_text,
        created_by: user
      )

      add_genre_events(issue)
      issue.sort_weekly_mix_positions!
      issue
    end

    private

    attr_reader :user, :today, :items_per_genre, :selected_event_ids, :selected_series_keys

    def draft_title
      "Wochenmix Test KW #{today.cweek}/#{today.cwyear} #{Time.current.strftime('%d.%m.%Y %H:%M')}"
    end

    def default_intro
      <<~TEXT.strip
        deine Event-Highlights der Woche, passend zu deinen Interessen und handverlesen statt wahllos zusammengestellt.
        Regelmäßig frisch. Persönlich für dich 🩵
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

    def add_genre_events(issue)
      position = 1

      HeaderGenreGroups.all.each do |group|
        events_for(group).each do |event|
          issue.newsletter_issue_items.create!(item: event, position:, section_key: group.slug, cta_label: "Zum Event")
          selected_event_ids.add(event.id)
          selected_series_keys.add(series_key_for(event))
          position += 1
        end
      end
    end

    def events_for(group)
      candidates = Event
        .published_live
        .joins(:genres)
        .includes(:event_series)
        .where(genres: { id: group.genre.id })
        .where("events.start_at >= ?", today.beginning_of_day)
        .where.not(id: selected_event_ids.to_a)
        .reorder(Arel.sql(Event.search_priority_order_sql), :start_at, :id)
        .limit(items_per_genre * 25)
        .to_a
        .reject { |event| selected_series_keys.include?(series_key_for(event)) }

      Public::Events::SeriesRepresentativeSelector.call(candidates).first(items_per_genre)
    end

    def series_key_for(event)
      event.event_series_id.presence || "event-#{event.id}"
    end
  end
end

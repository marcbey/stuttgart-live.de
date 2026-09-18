module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :design_preview, :design_preview_detail, :lane, :homepage_lane, :saved, :saved_lane, :search, :show, :related, :search_overlay, :termine ]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 12
    HOME_LANE_LIMIT = Public::Events::HomepageLanePager::DEFAULT_PER_PAGE
    HOME_LANE_LIST_LIMIT = 12
    HOME_HIGHLIGHTS_LANE_LIMIT = HOME_LANE_LIMIT + 4
    HOME_UNDER_30_PRICE_LIMIT = 30
    LANE_PAGE_LIMIT = Public::Events::HomepageLanePager::MAX_PER_PAGE
    HOME_CANDIDATE_LIMIT = 100
    SEARCH_OVERLAY_LIMIT = 6
    SEARCH_OVERLAY_IDLE_LIMIT = 10
    RELATED_EVENTS_PAGE_SIZE = 8
    SHOW_EVENT_SERIES_TERMS_LIMIT = 6
    SAVED_LANE_SLUG_LIMIT = 200
    RUSS_LIVE_PROMOTER_ID = "382".freeze
    REQUEST_PROFILE_HEADER = "X-Stuttgart-Live-Profile".freeze
    GERMAN_MONTH_NAMES = %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember].freeze
    HomepageLaneShell = Data.define(:events, :effective_series_ids, :series_counts_by_id, :next_cursor)

    before_action :set_browse_state, only: [ :index, :design_preview, :design_preview_detail, :lane, :homepage_lane, :saved, :saved_lane, :search, :show, :related, :search_overlay, :termine ]
    around_action :append_index_profile_headers, only: :index

    def index
      if params[:q].present?
        redirect_to(search_redirect_path, allow_other_host: false)
        return
      end

      respond_to do |format|
        format.html do
          assign_design_homepage
          render :design_preview
        end
        format.turbo_stream
      end
    end

    def design_preview
      if params[:q].present?
        redirect_to(search_redirect_path, allow_other_host: false)
        return
      end

      assign_design_homepage
    end

    def design_preview_detail
      assign_design_detail_event(design_preview_detail_event)
    end

    def search
      unless @browse_state.search_query_present?
        redirect_to events_path(event_date: @browse_state.event_date_param)
        return
      end

      relation = search_results_relation
      if should_redirect_search_result?(relation)
        event = relation.limit(1).first
        redirect_to event_path(event.slug, **@browse_state.route_params)
        return
      end

      @events = relation.to_a
      assign_design_chrome(saved_events: @events, include_homepage_saved_events: false)
    end

    def lane
      @lane = resolved_lane
      raise ActiveRecord::RecordNotFound if @lane.blank?

      assign_lane_page(@lane)
      assign_design_chrome(saved_events: @lane_events)
    end

    def homepage_lane
      @homepage_lane_page = homepage_lane_page(params[:lane], cursor: params[:cursor])
      raise ActiveRecord::RecordNotFound if @homepage_lane_page.blank?

      response.set_header("X-Homepage-Lane-Next-Cursor", @homepage_lane_page.next_cursor.to_s)
      response.set_header("X-Homepage-Lane-Has-More", @homepage_lane_page.next_cursor.present?.to_s)

      render partial: "public/events/homepage_lane_page",
             formats: [ :html ],
             locals: homepage_lane_render_locals(
               params[:lane],
               @homepage_lane_page,
               mode: params[:mode]
             )
    rescue Public::Events::HomepageLanePager::InvalidCursor
      head :bad_request
    end

    def saved
      assign_design_chrome
    end

    def saved_lane
      slugs = normalized_saved_lane_slugs
      if slugs.empty?
        render plain: ""
        return
      end

      @saved_lane_events = homepage_events_relation.where(slug: slugs).reorder(:start_at, :id).to_a
      if @saved_lane_events.empty?
        render plain: ""
        return
      end

      render partial: "public/events/saved_events_lane",
             locals: {
               browse_state: @browse_state,
               events: @saved_lane_events
             }
    end

    def show
      assign_design_detail_event(show_events_relation.find_by!(slug: params[:slug]))

      respond_to do |format|
        format.html { render :design_preview_detail }
      end
    end

    def related
      @event = show_events_relation.find_by!(slug: params[:slug])
      offset = related_events_offset
      @related_genre_lane = Public::Events::RelatedGenreLaneBuilder.new(
        event: @event,
        relation: show_related_genre_lane_events_relation,
        limit: offset + RELATED_EVENTS_PAGE_SIZE + 1
      ).call
      assign_related_events_page(offset:)

      if @related_events.empty?
        head :no_content
        return
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(
              "event-detail-related-events",
              partial: "public/events/event_rows",
              locals: related_event_rows_locals(@related_events, wrap: false)
            ),
            turbo_stream.replace(
              "event-detail-related-more",
              partial: "public/events/related_events_more",
              locals: related_events_more_locals
            )
          ]
        end
        format.html { redirect_to event_path(@event.slug, **@browse_state.route_params) }
      end
    end

    def termine
      @event = show_events_relation.find_by!(slug: params[:slug])
      @event_series_lane = Public::Events::EventSeriesLaneBuilder.new(
        event: @event,
        relation: show_event_series_lane_relation
      ).call

      raise ActiveRecord::RecordNotFound if @event_series_lane.blank?
    end

    def search_overlay
      @overlay = build_search_overlay

      render partial: "public/events/search_overlay",
             locals: {
               browse_state: @browse_state,
               overlay: @overlay,
               preview_results_only: params[:preview_results_only] == "true"
             }
    end

    def status
      browse_state = Public::Events::BrowseState.new(params)
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: helpers.public_events_index_path(browse_state, page: browse_state.page)
        return
      end

      apply_status!(@event, desired_status)
      Editorial::EventChangeLogger.log!(
        event: @event,
        action: "public_status_update",
        user: current_user,
        changed_fields: @event.saved_changes
      )

      respond_to do |format|
        format.turbo_stream do
          streams = []
          card_id = helpers.dom_id(@event, :card)

          if @event.live?
            streams << turbo_stream.replace(
              card_id,
              partial: "public/events/event_card",
              locals: {
                event: @event,
                card_slot: params[:card_slot].presence || :grid_default,
                browse_state: browse_state
              }
            )
          else
            streams << turbo_stream.remove(card_id)
          end

          render turbo_stream: streams
        end
        format.html do
          redirect_back fallback_location: helpers.public_events_index_path(browse_state, page: browse_state.page)
        end
      end
    end

    private

    def build_search_overlay
      Public::Events::Search::OverlayBuilder.build(
        query: @browse_state.query,
        idle_loader: -> { action_name == "search" ? [] : initial_search_overlay_events },
        event_loader: lambda {
          visible_events_relation(
            scope: searchable_index_events_relation,
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: @browse_state.query
          ).limit(SEARCH_OVERLAY_LIMIT).to_a
        },
        standard_event_loader: lambda {
          visible_events_relation(
            scope: searchable_index_events_relation,
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: @browse_state.query,
            structured: false
          ).limit(SEARCH_OVERLAY_LIMIT).to_a
        },
        genre_loader: lambda {
          Public::Events::Search::GenreSuggester.call(@browse_state.query)
        }
      )
    end

    def set_browse_state
      @browse_state = Public::Events::BrowseState.new(params)
    end

    def visible_events_relation(scope: index_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil, structured: true)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query,
        structured: structured
      ).call
    end

    def published_visible_events_relation(scope: published_future_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil, structured: true)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query,
        structured: structured
      ).call
    end

    def index_events_relation
      return published_future_events_relation unless authenticated?

      future_events_relation
    end

    def searchable_index_events_relation
      relation = search_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
      return relation.where(status: "published").where("published_at IS NULL OR published_at <= ?", Time.current) unless authenticated?

      exclude_scheduled_published_events(relation)
    end

    def future_events_relation
      list_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def published_future_events_relation
      published_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def assign_homepage_sections
      @home_featured_lane = Public::Events::LaneDirectory.highlights
      @home_all_stuttgart_lane = Public::Events::LaneDirectory.all_stuttgart
      @home_tagestipp_lane = Public::Events::LaneDirectory.tagestipp
      @home_under_30_lane = Public::Events::LaneDirectory.under_30

      empty_lane = empty_homepage_lane_shell
      @home_featured_available = homepage_highlights_available?
      home_featured_page = @home_featured_available ? homepage_lane_page_or_empty("highlights", per_page: HOME_HIGHLIGHTS_LANE_LIMIT) : empty_lane
      home_featured_list_page = @home_featured_available ? homepage_lane_page_or_empty("highlights", per_page: HOME_LANE_LIST_LIMIT) : empty_lane
      @home_featured_events = home_featured_page.events
      @home_featured_effective_series_ids = home_featured_page.effective_series_ids
      @home_featured_series_counts_by_id = home_featured_page.series_counts_by_id
      @home_featured_next_cursor = home_featured_page.next_cursor
      @home_featured_list_next_cursor = home_featured_list_page.next_cursor

      @home_genre_lanes = homepage_genre_lane_sections
      @home_genre_tag_cloud_genres = []
      @home_highlight_events = empty_lane.events
      @home_highlight_effective_series_ids = empty_lane.effective_series_ids
      @home_highlight_series_counts_by_id = empty_lane.series_counts_by_id
      @home_highlight_next_cursor = empty_lane.next_cursor
      @home_tagestipp_available = tagestipp_available?
      home_tagestipp_page = @home_tagestipp_available ? homepage_lane_page_or_empty("tagestipp", per_page: HOME_LANE_LIMIT) : empty_lane
      @home_tagestipp_events = home_tagestipp_page.events
      @home_tagestipp_effective_series_ids = home_tagestipp_page.effective_series_ids
      @home_tagestipp_series_counts_by_id = home_tagestipp_page.series_counts_by_id
      @home_tagestipp_next_cursor = home_tagestipp_page.next_cursor
      @home_under_30_available = under_30_available?
      home_under_30_page = @home_under_30_available ? homepage_lane_page_or_empty("under_30", per_page: HOME_LANE_LIMIT) : empty_lane
      @home_under_30_events = home_under_30_page.events
      @home_under_30_effective_series_ids = home_under_30_page.effective_series_ids
      @home_under_30_series_counts_by_id = home_under_30_page.series_counts_by_id
      @home_under_30_next_cursor = home_under_30_page.next_cursor
      @home_seo_events = homepage_seo_events
    end

    def assign_design_homepage
      assign_homepage_sections
      assign_homepage_promotion_banners
      @design_preview_news_posts = BlogPost.published_live.with_attached_cover_image.limit(6).to_a
      @design_preview_mix_events = design_preview_mix_events
      @design_preview_series_counts_by_id = Public::Events::SeriesCountsByIdQuery.call(design_preview_series_events)
      @design_preview_search_overlay = build_search_overlay
    end

    def design_preview_series_events
      promotion_banner_events = Array(@all_promotion_banners).filter_map do |banner|
        banner[:record] if banner[:type] == :event
      end

      (
        Array(@home_featured_events) +
        Array(@home_tagestipp_events) +
        Array(@home_under_30_events) +
        Array(@design_preview_mix_events) +
        Array(@home_genre_lanes).flat_map { |lane| Array(lane.events) } +
        promotion_banner_events
      ).compact.uniq(&:id)
    end

    def assign_design_detail_event(event)
      assign_homepage_sections
      @design_preview_search_overlay = build_search_overlay
      @event = event
      @design_preview_detail_format_images = design_preview_detail_format_images(@event)
      @primary_offer = @event.public_ticket_offer
      @event_series_lane = Public::Events::EventSeriesLaneBuilder.new(
        event: @event,
        relation: show_event_series_lane_relation,
        exclude_event: @event
      ).call
      @related_genre_lane = Public::Events::RelatedGenreLaneBuilder.new(
        event: @event,
        relation: show_related_genre_lane_events_relation,
        limit: RELATED_EVENTS_PAGE_SIZE + 1
      ).call
      assign_related_events_page(offset: 0)
    end

    def assign_design_chrome(saved_events: [], include_homepage_saved_events: true)
      assign_homepage_sections
      @design_preview_search_overlay = build_search_overlay
      @design_chrome_genre_lanes = @home_genre_lanes
      homepage_saved_events = if include_homepage_saved_events
        Array(@home_featured_events) +
          Array(@home_tagestipp_events) +
          Array(@home_under_30_events) +
          Array(@home_genre_lanes).flat_map { |lane| Array(lane.events) }
      else
        []
      end
      @design_chrome_saved_events = (Array(saved_events) + homepage_saved_events).compact.uniq(&:id)
    end

    def should_redirect_search_result?(relation)
      return false unless @browse_state.search_query_present?
      return false unless @browse_state.page == 1

      relation.limit(2).count == 1
    end

    def search_results_relation
      visible_events_relation(
        scope: searchable_index_events_relation,
        filter: search_filter,
        event_date: @browse_state.event_date,
        query: @browse_state.query
      )
    end

    def search_redirect_path
      return search_path(**@browse_state.route_params) if @browse_state.search_query_present?

      events_path(event_date: @browse_state.event_date_param)
    end

    def published_events_relation
      detail_events_relation
        .published_live
    end

    def homepage_events_relation
      list_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def design_preview_mix_events
      lanes = Public::Events::HomepageGenreLanesBuilder.new(
        relation: scoped_homepage_all_relation,
        limit: HOME_LANE_LIMIT
      ).call

      interleave_design_preview_mix_lanes(lanes)
    end

    def interleave_design_preview_mix_lanes(lanes)
      event_groups = lanes.map { |lane| shuffled_design_preview_mix_events(lane) }.reject(&:empty?)
      mixed_events = []

      event_groups.cycle do |events|
        break if event_groups.all?(&:empty?) || mixed_events.size >= HOME_LANE_LIMIT * 2

        event = events.shift
        mixed_events << event if event.present? && mixed_events.none? { |mixed_event| mixed_event.id == event.id }
      end

      mixed_events
    end

    def shuffled_design_preview_mix_events(lane)
      seed = "#{Time.zone.today.iso8601}:#{lane.group.slug}"
      lane.events.shuffle(random: Random.new(seed.bytes.sum))
    end

    def design_preview_detail_event
      return show_events_relation.find_by!(slug: params[:slug]) if params[:slug].present?

      preferred_event = design_preview_detail_preferred_event
      return preferred_event if preferred_event.present?

      upcoming_events = show_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .reorder(:start_at, :id)
        .limit(80)
        .to_a

      upcoming_events.find { |event| event.image_for(slot: :detail_hero, breakpoint: :desktop).present? } ||
        upcoming_events.first ||
        show_events_relation.published_live.reorder(start_at: :desc, id: :desc).first!
    end

    def design_preview_detail_preferred_event
      preferred_slugs = %w[
        mamma-mia-das-musical-2027-05-05
        jolle-2026-09-16
        twin-noir-2026-10-02
        levka-2027-03-04
      ]
      scope = show_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)

      preferred_slugs.filter_map { |slug| scope.find_by(slug:) }.first
    end

    def design_preview_detail_format_images(event)
      current_image = event.image_for(slot: :detail_hero, breakpoint: :desktop) ||
        event.image_for(slot: :grid_default, breakpoint: :desktop)

      ([ current_image ] + event.slider_images).compact.uniq { |image| [ image.class.name, image.id ] }.map do |image|
        {
          kind: design_preview_detail_image_bucket(image) || :image,
          image: image
        }
      end
    end

    def design_preview_detail_image_bucket(image)
      return image.aspect_hint.to_sym if image.respond_to?(:aspect_hint) && buckets_aspect_hint?(image.aspect_hint)
      return unless image.respond_to?(:file) && image.file.attached?

      width = image.file.blob.metadata["width"].to_f
      height = image.file.blob.metadata["height"].to_f
      return if width <= 0 || height <= 0

      ratio = width / height
      return :portrait if ratio < 0.9
      return :landscape if ratio > 1.12

      :square
    end

    def buckets_aspect_hint?(aspect_hint)
      %w[portrait square landscape].include?(aspect_hint.to_s)
    end

    def search_events_relation
      list_events_relation
    end

    def homepage_genre_lane_sections
      slugs = AppSetting.normalize_slug_list(AppSetting.homepage_genre_lane_slugs)
      return [] if slugs.empty?

      groups_by_slug = Genre.where(slug: slugs).index_by(&:slug)
      public_paths_by_slug = Public::Events::LaneDirectory.public_paths_for_genre_slugs(slugs)
      initial_lane_rendered = false

      slugs.filter_map do |slug|
        group = groups_by_slug[slug]
        next if group.blank?
        next unless homepage_genre_lane_available?(group)

        lane_page = initial_lane_rendered ? empty_homepage_lane_shell : homepage_lane_page_or_empty("genre:#{group.slug}", per_page: HOME_LANE_LIMIT)
        initial_lane_rendered ||= lane_page.events.present?

        Public::Events::HomepageGenreLanesBuilder::Lane.new(
          group: group,
          events: lane_page.events,
          effective_series_ids: lane_page.effective_series_ids,
          series_counts_by_id: lane_page.series_counts_by_id,
          public_path: public_paths_by_slug[group.slug],
          next_cursor: lane_page.next_cursor
        )
      end
    end

    def homepage_genre_tag_cloud_genres
      Public::Events::HomepageGenreTagCloudBuilder.new(relation: homepage_events_relation).call
    end

    def empty_homepage_lane_shell
      HomepageLaneShell.new(
        events: [],
        effective_series_ids: [],
        series_counts_by_id: {},
        next_cursor: nil
      )
    end

    def homepage_highlights_available?
      lean_homepage_highlights_relation.exists? || lean_homepage_all_relation.exists?
    end

    def tagestipp_available?
      lean_tagestipp_relation.exists?
    end

    def under_30_available?
      lean_under_30_relation.exists?
    end

    def homepage_genre_lane_available?(group)
      lean_homepage_events_relation
        .joins(:genres)
        .where(genres: { id: group.id })
        .distinct
        .exists?
    end

    def homepage_seo_events
      lean_homepage_all_relation
        .reorder(:start_at, :id)
        .select(:id, :slug, :artist_name, :title, :start_at)
        .limit(50)
        .to_a
    end

    def homepage_lane_page(identifier, cursor: nil, per_page: nil)
      cursor_payload = Public::Events::HomepageLanePager.decode_cursor(cursor)
      raise Public::Events::HomepageLanePager::InvalidCursor if cursor.present? && cursor_payload.blank?

      lane_relation, context = homepage_lane_relation_and_context(identifier, cursor_payload:)
      return if lane_relation.nil?

      Public::Events::HomepageLanePager.new(
        relation: lane_relation,
        context: context,
        cursor: cursor,
        per_page: normalized_homepage_lane_per_page(per_page)
      ).call
    end

    def homepage_lane_page_or_empty(identifier, per_page:)
      homepage_lane_page(identifier, per_page:) || empty_homepage_lane_shell
    end

    def homepage_lane_relation_and_context(identifier, cursor_payload: nil)
      lane_key, lane_slug = normalized_homepage_lane_identifier(identifier)

      case lane_key
      when "highlights"
        homepage_highlights_relation_and_context(cursor_payload:)
      when "all_stuttgart"
        [
          scoped_homepage_all_relation.reorder(:start_at, :id),
          homepage_lane_context(lane: "all_stuttgart")
        ]
      when "tagestipp"
        [
          tagestipp_relation,
          homepage_lane_context(lane: "tagestipp")
        ]
      when "under_30"
        [
          under_30_relation,
          homepage_lane_context(lane: "under_30")
        ]
      when "genre"
        group = Genre.find_by(slug: lane_slug)
        return if group.blank?

        [
          homepage_events_relation.joins(:genres).where(genres: { id: group.id }).distinct.reorder(:start_at, :id),
          { lane: "genre", slug: group.slug }
        ]
      end
    end

    def homepage_highlights_relation_and_context(cursor_payload: nil)
      cursor_variant = cursor_payload&.dig("context", "variant")
      highlights_relation = scoped_homepage_highlights_relation
      variant = cursor_variant.presence || (highlights_relation.exists? ? "primary" : "fallback")
      relation = variant == "fallback" ? scoped_homepage_all_relation.reorder(:start_at, :id) : highlights_relation

      [
        relation,
        homepage_lane_context(lane: "highlights", variant: variant)
      ]
    end

    def scoped_homepage_all_relation
      published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      )
    end

    def scoped_homepage_highlights_relation
      published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_SKS,
        event_date: @browse_state.event_date,
        query: nil
      ).reorder(:start_at, :id)
    end

    def under_30_relation
      scoped_homepage_all_relation
        .joins(:event_offers)
        .merge(EventOffer.active_ticket)
        .where.not(min_price: nil)
        .where("events.min_price > 0")
        .where("events.min_price <= ?", HOME_UNDER_30_PRICE_LIMIT)
        .distinct
        .reorder(:start_at, :id)
    end

    def lean_homepage_events_relation
      Event.published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def lean_homepage_all_relation
      published_visible_events_relation(
        scope: lean_homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      )
    end

    def lean_homepage_highlights_relation
      published_visible_events_relation(
        scope: lean_homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_SKS,
        event_date: @browse_state.event_date,
        query: nil
      ).reorder(:start_at, :id)
    end

    def lean_tagestipp_relation
      published_visible_events_relation(
        scope: lean_homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: nil,
        query: nil
      ).reorder(:start_at, :id)
    end

    def lean_under_30_relation
      lean_homepage_all_relation
        .joins(:event_offers)
        .merge(EventOffer.active_ticket)
        .where.not(min_price: nil)
        .where("events.min_price > 0")
        .where("events.min_price <= ?", HOME_UNDER_30_PRICE_LIMIT)
        .distinct
    end

    def normalized_homepage_lane_identifier(identifier)
      value = identifier.to_s
      return [ "genre", value.delete_prefix("genre:").parameterize ] if value.start_with?("genre:")

      [ value, nil ]
    end

    def homepage_lane_context(**values)
      values.merge(
        event_date: @browse_state.event_date_param,
        filter: @browse_state.filter
      ).compact
    end

    def normalized_homepage_lane_per_page(default = nil)
      (params[:per_page].presence || default || HOME_LANE_LIMIT).to_i
    end

    def homepage_lane_render_locals(identifier, lane_page, mode:)
      lane_key, lane_slug = normalized_homepage_lane_identifier(identifier)
      {
        lane_key: lane_key,
        lane_slug: lane_slug,
        mode: normalized_homepage_lane_render_mode(mode),
        page: lane_page,
        browse_state: @browse_state,
        strict_proxy: helpers.homepage_media_strict_proxy?
      }.merge(homepage_lane_card_options(lane_key))
    end

    def normalized_homepage_lane_render_mode(mode)
      return "rows" if mode.to_s == "rows"
      return "design_cards" if mode.to_s == "design_cards"

      "cards"
    end

    def homepage_lane_card_options(lane_key)
      case lane_key
      when "all_stuttgart"
        { card_variant: "editorial", header_variant: :editorial }
      when "tagestipp"
        { card_variant: "spotlight", header_variant: :tagestipp }
      when "under_30"
        { card_variant: "compact", header_variant: :editorial }
      else
        {}
      end
    end

    def assign_homepage_promotion_banners
      event_banners = Event.promotion_banner_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .select(&:promotion_banner_display_image_present?)
        .map { |event| { type: :event, record: event } }
      highlight_slider_event_banners = Event.published_live
        .where(highlighted: true)
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .includes(
          :venue_record,
          promotion_banner_image_attachment: :blob,
          promotion_banner_landscape_image_attachment: :blob,
          highlight_video_file_attachment: :blob,
          highlight_landscape_video_file_attachment: :blob,
          event_images: [ file_attachment: :blob ]
        )
        .select(&:promotion_banner_display_image_present?)
        .map { |event| { type: :event, record: event } }
      news_banners = BlogPost.promotion_banner_live
        .select { |blog_post| blog_post.promotion_banner_image.attached? || blog_post.promotion_banner_landscape_image.attached? }
        .map { |blog_post| { type: :news, record: blog_post } }

      sorted_banners = (event_banners + news_banners).sort_by { |banner| promotion_banner_sort_key(banner) }
      slider_banners = (event_banners + highlight_slider_event_banners + news_banners)
        .uniq { |banner| [ banner[:type], banner[:record].id ] }
        .sort_by { |banner| promotion_banner_sort_key(banner) }

      @all_promotion_banners = homepage_promotion_slider_banners(slider_banners)
      @priority_promotion_banner = @all_promotion_banners.first
      @promotion_banners_by_lane_position = sorted_banners
        .select { |banner| banner[:record].promotion_banner_lane_position.present? }
        .group_by { |banner| banner[:record].promotion_banner_lane_position }
    end

    def homepage_promotion_slider_banners(banners)
      return banners unless banners.many? && !Rails.env.test?

      banners.rotate(homepage_promotion_banner_rotation_offset(banners.length))
    end

    def homepage_promotion_banner_rotation_offset(length)
      Time.zone.today.yday % length
    end

    def promotion_banner_sort_key(banner)
      record = banner[:record]
      lane_position = record.promotion_banner_lane_position || Event::DEFAULT_PROMOTION_BANNER_LANE_POSITION

      case banner[:type]
      when :event
        [ lane_position, 0, record.start_at, record.id ]
      else
        [ lane_position, 1, -record.published_at.to_i, -record.id ]
      end
    end

    def initial_search_overlay_events
      promotion_events = initial_search_overlay_events_for(search_overlay_idle_relation.where(promotion_banner: true))
      highlighted_events = initial_search_overlay_events_for(search_overlay_idle_relation.where(highlighted: true))
      sks_events = initial_search_overlay_events_for(search_overlay_idle_relation.merge(Event.sks_promoters))

      deduplicate_priority_events(promotion_events, highlighted_events, sks_events).first(SEARCH_OVERLAY_IDLE_LIMIT)
    end

    def initial_search_overlay_events_for(scope)
      visible_events_relation(
        scope: scope,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      ).limit(SEARCH_OVERLAY_IDLE_LIMIT).to_a
    end

    def search_overlay_idle_relation
      search_events_relation
        .where(status: "published")
        .where("published_at IS NULL OR published_at <= ?", Time.current)
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def deduplicate_priority_events(*groups)
      groups.flatten.each_with_object({}) do |event, deduplicated_events|
        deduplicated_events[event.id] ||= event
      end.values
    end

    def normalized_saved_lane_slugs
      Array(params[:slugs]).filter_map do |slug|
        normalized_slug = slug.to_s.strip
        normalized_slug if normalized_slug.present?
      end.uniq.first(SAVED_LANE_SLUG_LIMIT)
    end

    def search_filter
      return Public::Events::BrowseState::FILTER_ALL if @browse_state.search_query_present?

      @browse_state.filter
    end

    def show_events_relation
      return published_events_relation unless authenticated?

      detail_events_relation
    end

    def show_related_genre_lane_events_relation
      list_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def show_event_series_lane_relation
      relation = list_events_relation

      authenticated? ? relation : relation.published_live
    end

    def assign_related_events_page(offset:)
      @related_events = @related_genre_lane&.events&.slice(offset, RELATED_EVENTS_PAGE_SIZE) || []
      @related_events_next_offset = offset + @related_events.size
      @related_events_has_more =
        @related_genre_lane.present? && @related_genre_lane.events.size > @related_events_next_offset
    end

    def related_events_offset
      [ params[:offset].to_i, 0 ].max
    end

    def related_event_rows_locals(events, wrap:)
      {
        events: events,
        browse_state: @browse_state,
        wrap: wrap,
        container_id: (wrap ? "event-detail-related-events" : nil),
        effective_series_ids: @related_genre_lane.effective_series_ids,
        series_counts_by_id: @related_genre_lane.series_counts_by_id
      }
    end

    def related_events_more_locals
      {
        event: @event,
        browse_state: @browse_state,
        next_offset: @related_events_next_offset,
        has_more: @related_events_has_more
      }
    end

    def detail_events_relation
      Event.includes(
        :llm_enrichment,
        :genres,
        :sub_genres,
        :event_offers,
        :import_event_images,
        highlight_video_file_attachment: :blob,
        highlight_landscape_video_file_attachment: :blob,
        event_images: [ file_attachment: :blob ],
        venue_record: [ logo_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      )
    end

    def list_events_relation
      Event.includes(
        :venue_record,
        :event_offers,
        :import_event_images,
        highlight_video_file_attachment: :blob,
        highlight_landscape_video_file_attachment: :blob,
        event_images: [ file_attachment: :blob ]
      )
    end

    def tagestipp_relation
      published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: nil,
        query: nil
      ).reorder(:start_at, :id)
    end

    def assign_lane_page(lane)
      case lane.key
      when "highlights"
        if explicit_sks_filter?
          relation = published_visible_events_relation(
            scope: homepage_events_relation.merge(Event.sks_promoters),
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: nil
          ).reorder(:start_at, :id)
          @lane_series_counts_by_id = public_series_counts_for_relation(relation)
          @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
          @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
          return
        end

        scoped_highlights = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: Public::Events::BrowseState::FILTER_SKS,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_series_counts_by_id = public_series_counts_for_relation(scoped_highlights)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(scoped_highlights)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(scoped_highlights.to_a)

        return unless @lane_events.empty?

        fallback_relation = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_series_counts_by_id = public_series_counts_for_relation(fallback_relation)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(fallback_relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(fallback_relation.to_a)
      when "all_stuttgart"
        relation = all_stuttgart_month_relation
        @lane_series_counts_by_id = public_series_counts_for_relation(relation)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "tagestipp"
        relation = tagestipp_relation
        @lane_series_counts_by_id = public_series_counts_for_relation(relation)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "under_30"
        relation = under_30_relation
        @lane_series_counts_by_id = public_series_counts_for_relation(relation)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "russ_live"
        relation = published_visible_events_relation(
          scope: homepage_events_relation.merge(Event.sks_promoters),
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_series_counts_by_id = public_series_counts_for_relation(relation)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "genre"
        lane_page = homepage_lane_page("genre:#{lane.group.slug}", per_page: LANE_PAGE_LIMIT)
        raise ActiveRecord::RecordNotFound if lane_page.blank?

        @lane_effective_series_ids = lane_page.effective_series_ids
        @lane_series_counts_by_id = lane_page.series_counts_by_id
        @lane_events = lane_page.events
        @lane_next_cursor = lane_page.next_cursor
        @lane_list_next_cursor = lane_page.next_cursor
        @lane_lazy_id = "genre:#{lane.group.slug}" if @lane_next_cursor.present?
        @lane_lazy_url = helpers.homepage_lane_events_path(
          event_date: @browse_state.event_date_param,
          filter: @browse_state.filter
        ) if @lane_lazy_id.present?
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def resolved_lane
      return Public::Events::LaneDirectory.resolve(params[:lane]) if params[:lane].present?

      Public::Events::LaneDirectory.resolve(params[:lane_slug])
    end

    def all_stuttgart_relation
      published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: nil,
        query: nil
      ).reorder(:start_at, :id)
    end

    def all_stuttgart_month_relation
      relation = all_stuttgart_relation
      @lane_months = all_stuttgart_months_for(relation)
      @lane_month_labels_by_value = all_stuttgart_month_labels_by_value(@lane_months)
      @lane_selected_month = selected_all_stuttgart_month(@lane_months)
      @lane_title = all_stuttgart_month_title(@lane_selected_month)

      month_relation = if @lane_selected_month.blank?
        relation
      else
        relation.where(
          start_at: @lane_selected_month.beginning_of_month.beginning_of_day..@lane_selected_month.end_of_month.end_of_day
        )
      end

      @all_stuttgart_selected_genre = selected_all_stuttgart_genre
      @all_stuttgart_genres = all_stuttgart_genres_for(month_relation)
      @all_stuttgart_genres |= [ @all_stuttgart_selected_genre ] if @all_stuttgart_selected_genre.present?
      @all_stuttgart_selected_location = selected_all_stuttgart_location(month_relation)
      @all_stuttgart_locations = all_stuttgart_locations_for(month_relation)
      @all_stuttgart_locations |= [ @all_stuttgart_selected_location ] if @all_stuttgart_selected_location.present?

      filtered_relation = month_relation
      filtered_relation = filtered_relation.joins(:genres).where(genres: { id: @all_stuttgart_selected_genre.id }).distinct if @all_stuttgart_selected_genre.present?
      filtered_relation = filtered_relation.left_outer_joins(:venue_record).where(venues: { name: @all_stuttgart_selected_location }) if @all_stuttgart_selected_location.present?

      filtered_relation
    end

    def all_stuttgart_genres_for(relation)
      genre_ids = relation.except(:order).joins(:genres).distinct.pluck("genres.id")

      Genre.where(id: genre_ids).order(:name).to_a
    end

    def all_stuttgart_locations_for(relation)
      relation
        .except(:order)
        .left_outer_joins(:venue_record)
        .where.not(venues: { name: [ nil, "" ] })
        .pluck("venues.name")
        .map { |venue| venue.to_s.strip }
        .reject(&:blank?)
        .uniq
        .sort_by(&:downcase)
    end

    def selected_all_stuttgart_genre
      requested_genre = params[:event_genre].to_s.strip.parameterize
      return if requested_genre.blank?

      Genre.find_by(slug: requested_genre)
    end

    def selected_all_stuttgart_location(relation)
      requested_location = params[:event_location].to_s.strip
      return if requested_location.blank?

      all_stuttgart_locations_for(relation).find { |location| location == requested_location }
    end

    def all_stuttgart_months_for(relation)
      relation.pluck(:start_at).filter_map do |start_at|
        start_at&.to_date&.beginning_of_month
      end.uniq
    end

    def selected_all_stuttgart_month(months)
      requested_month = parsed_all_stuttgart_month(params[:event_month])
      return requested_month if requested_month.present?

      next_month = Time.zone.today.next_month.beginning_of_month
      return next_month if months.include?(next_month)

      current_month = Time.zone.today.beginning_of_month
      return current_month if months.include?(current_month)

      months.first || current_month
    end

    def parsed_all_stuttgart_month(value)
      return if value.blank?

      Date.strptime(value.to_s, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end

    def all_stuttgart_month_title(month)
      return Public::Events::LaneDirectory.all_stuttgart.title if month.blank?

      "#{all_stuttgart_month_label(month)} #{month.year}"
    end

    def all_stuttgart_month_labels_by_value(months)
      months.index_with { |month| all_stuttgart_month_label(month) }
    end

    def all_stuttgart_month_label(month)
      GERMAN_MONTH_NAMES.fetch(month.month - 1)
    end

    def apply_status!(event, status)
      before_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")

      event.status = status
      event.auto_published = false
      event.sync_publication_fields(user: current_user)
      event.save!
      after_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")
      before_values != after_values
    end

    def effective_public_series_ids_for_relation(relation)
      Public::Events::EffectiveSeriesIdsQuery.call(relation)
    end

    def public_series_counts_for_relation(relation)
      Public::Events::SeriesCountsByIdQuery.call(relation)
    end

    def explicit_sks_filter?
      params[:filter].to_s == Public::Events::BrowseState::FILTER_SKS
    end

    def exclude_scheduled_published_events(relation)
      events = Event.arel_table
      publicly_live = events[:status].eq("published").and(events[:published_at].eq(nil).or(events[:published_at].lteq(Time.current)))

      relation.where(events[:status].not_eq("published").or(publicly_live))
    end

    def render_not_found
      respond_to do |format|
        format.html do
          @browse_state ||= Public::Events::BrowseState.new(params)
          render "public/events/not_found", status: :not_found
        end
        format.any { head :not_found }
      end
    end

    def append_index_profile_headers
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      return unless index_profile_requested?

      wall_ms = elapsed_milliseconds_since(started_at)
      profile_payload = {
        wall_ms: wall_ms,
        view_ms: view_runtime.to_f.round(1),
        sql_ms: db_runtime.to_f.round(1),
        queries: ActiveRecord::RuntimeRegistry.stats.queries_count,
        cached_queries: ActiveRecord::RuntimeRegistry.stats.cached_queries_count
      }

      response.set_header(REQUEST_PROFILE_HEADER, profile_payload.map { |key, value| "#{key}=#{value}" }.join(", "))
      response.set_header("Server-Timing", server_timing_header(profile_payload))
    end

    def index_profile_requested?
      params[:profile].present? || request.headers[REQUEST_PROFILE_HEADER].present?
    end

    def elapsed_milliseconds_since(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(1)
    end

    def server_timing_header(profile_payload)
      [
        "app;dur=#{profile_payload[:wall_ms]}",
        "view;dur=#{profile_payload[:view_ms]}",
        "sql;dur=#{profile_payload[:sql_ms]}"
      ].join(", ")
    end
  end
end

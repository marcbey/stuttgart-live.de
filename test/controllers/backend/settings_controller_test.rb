require "test_helper"

class Backend::SettingsControllerTest < ActionDispatch::IntegrationTest
  VALID_LLM_ENRICHMENT_PROMPT = <<~TEXT.strip
    Nutze search_results und candidates für homepage_link, instagram_link, facebook_link und youtube_link.
    Ermittle venue_external_url direkt.
    {{input_json}}
  TEXT

  setup do
    @admin = users(:two)
    @editor = users(:one)
    reset_settings!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "admin can edit settings with tab shell and default section" do
    sign_in_as(@admin)
    seed_all_settings!
    create_homepage_genre_snapshot

    get edit_backend_settings_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Einstellungen"
    assert_select "[data-controller='settings-tabs']", count: 1
    assert_select "[role='tab']", count: 8
    assert_select "#settings-tab-meta-connection[aria-selected='true']", count: 1
    assert_select "article.social-post-card", count: 2
    assert_select "form[action='#{backend_settings_path(section: :sks_promoter_ids)}'] textarea[name='app_setting[sks_promoter_ids_text]']", count: 0
    assert_select ".social-post-card .social-post-card-header .backend-section-header-actions a[href='#{start_instagram_backend_meta_connection_path}'][data-turbo='false']",
                  text: "Instagram verbinden",
                  count: 1
    assert_select ".social-post-card .social-post-card-header .backend-section-header-actions a.button-save-primary[href='#{start_facebook_backend_meta_connection_path}'][data-turbo='false']",
                  text: "Facebook verbinden",
                  count: 1
    assert_select "form[action='#{refresh_status_backend_meta_connection_path}'] button", text: "Status prüfen", count: 0
    assert_select "textarea[name='app_setting[llm_enrichment_prompt_template_text]']", count: 0
  end

  test "meta page selection keeps selected page action in its card" do
    sign_in_as(@admin)
    facebook_connection = create_facebook_connection_with_pages!
    selected_page = facebook_connection.selected_facebook_page_target
    other_page = facebook_connection.social_connection_targets.facebook_pages.where(selected: false).first

    with_stubbed_meta_connection_state(facebook_connection:) do
      get edit_backend_settings_url(section: :meta_connection)
    end

    assert_response :success

    document = Nokogiri::HTML5(response.body)
    facebook_card = document.at_css("article.meta-platform-card-facebook")
    selected_row = page_target_row_for(facebook_card, selected_page.display_name)
    other_row = page_target_row_for(facebook_card, other_page.display_name)

    assert_equal 2, document.css("article.social-post-card").size
    assert_equal "Seite speichern", facebook_card.at_css("form.meta-page-target-selector input[type='submit']")&.attribute("value")&.value
    assert_equal selected_page.id.to_s, facebook_card.at_css("form.meta-page-target-selector select[name='target_id'] option[selected]")&.attribute("value")&.value
    assert facebook_card.css("button").none? { |button| button.text.strip == "Seite auswählen" }
    assert_equal "Ausgewählt", selected_row.at_css(".status-badge")&.text&.strip
    assert_equal "Verfügbar", other_row.at_css(".status-badge")&.text&.strip
  end

  test "meta publishing shows disconnect actions inside connected platform cards" do
    sign_in_as(@admin)
    instagram_connection = create_instagram_connection!
    facebook_connection = create_facebook_connection_with_pages!

    with_stubbed_meta_connection_state(instagram_connection:, facebook_connection:) do
      get edit_backend_settings_url(section: :meta_connection)
    end

    assert_response :success

    document = Nokogiri::HTML5(response.body)
    instagram_card = document.at_css("article.meta-platform-card-instagram")
    facebook_card = document.at_css("article.meta-platform-card-facebook")

    assert_equal "Verbindung trennen", instagram_card.at_css("form[action='#{disconnect_instagram_backend_meta_connection_path}'] button")&.text&.strip
    assert_equal "Verbindung trennen", facebook_card.at_css("form[action='#{disconnect_facebook_backend_meta_connection_path}'] button")&.text&.strip
  end

  test "admin can open specific section via query param" do
    sign_in_as(@admin)
    seed_all_settings!

    get edit_backend_settings_url(section: :llm_genre_grouping)

    assert_response :success
    assert_select "#settings-tab-llm-genre-grouping[aria-selected='true']", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_genre_grouping)}'] select[name='app_setting[llm_genre_grouping_model]']", count: 1
    assert_select "option[value='gpt-5.4']", text: "GPT-5.4", count: 1
    assert_select "textarea[name='app_setting[sks_promoter_ids_text]']", count: 0
  end

  test "invalid section falls back to default tab" do
    sign_in_as(@admin)

    get edit_backend_settings_url(section: :unknown)

    assert_response :success
    assert_select "#settings-tab-meta-connection[aria-selected='true']", count: 1
  end

  test "admin can load a section partial" do
    sign_in_as(@admin)
    seed_all_settings!

    get section_backend_settings_url(section: :llm_enrichment)

    assert_response :success
    assert_select "section.settings-group", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_enrichment)}'] select[name='app_setting[llm_enrichment_model]']", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_enrichment)}'] input[name='app_setting[llm_enrichment_temperature]']", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_enrichment)}'] select[name='app_setting[llm_enrichment_web_search_provider]']", count: 1
    assert_select ".settings-tabs-nav", count: 0
  end

  test "editor cannot access settings" do
    sign_in_as(@editor)

    get edit_backend_settings_url

    assert_redirected_to backend_root_url
  end

  test "admin can update sks promoter ids without touching other settings" do
    sign_in_as(@admin)
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5.1")

    patch backend_settings_url(section: :sks_promoter_ids), params: {
      app_setting: {
        sks_promoter_ids_text: "900\n901, 902"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :sks_promoter_ids)
    assert_equal %w[900 901 902], AppSetting.sks_promoter_ids
    assert_equal "gpt-5.1", AppSetting.llm_enrichment_model
  end

  test "admin can update llm enrichment section" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-5-mini",
        llm_enrichment_prompt_template_text: VALID_LLM_ENRICHMENT_PROMPT,
        llm_enrichment_temperature: "0.3",
        llm_enrichment_web_search_provider: "openwebninja"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :llm_enrichment)
    assert_equal "gpt-5-mini", AppSetting.llm_enrichment_model
    assert_equal VALID_LLM_ENRICHMENT_PROMPT, AppSetting.llm_enrichment_prompt_template
    assert_equal 0.3, AppSetting.llm_enrichment_temperature
    assert_equal "openwebninja", AppSetting.llm_enrichment_web_search_provider
  end

  test "admin can update llm genre grouping section with gpt-5.4" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_genre_grouping), params: {
      app_setting: {
        llm_genre_grouping_model: "gpt-5.4",
        llm_genre_grouping_prompt_template_text: "Gruppiere sauber\n{{group_count}}\n{{input_json}}",
        llm_genre_grouping_group_count: "35"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :llm_genre_grouping)
    assert_equal "gpt-5.4", AppSetting.llm_genre_grouping_model
    assert_equal "Gruppiere sauber\n{{group_count}}\n{{input_json}}", AppSetting.llm_genre_grouping_prompt_template
    assert_equal 35, AppSetting.llm_genre_grouping_group_count
  end

  test "admin can update homepage genre lanes section" do
    sign_in_as(@admin)
    snapshot = create_homepage_genre_snapshot

    patch backend_settings_url(section: :homepage_genre_lanes), params: {
      app_setting: {
        public_genre_grouping_snapshot_id: snapshot.id,
        homepage_genre_lane_slugs: [ "rock-alternative", "pop-mainstream" ]
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot.id)
    assert_equal snapshot.id, AppSetting.public_genre_grouping_snapshot_id
    assert_equal [ "rock-alternative", "pop-mainstream" ], snapshot.reload.homepage_genre_lane_configuration.lane_slugs
  end

  test "homepage genre lanes section shows the stored configuration of the selected snapshot" do
    sign_in_as(@admin)
    snapshot_one = create_homepage_genre_snapshot(selected: true, lane_slugs: [ "rock-alternative" ])
    snapshot_two = create_homepage_genre_snapshot(lane_slugs: [ "pop-mainstream" ])

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot_two.id)

    assert_response :success
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='pop-mainstream'][checked='checked']", count: 1
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='rock-alternative'][checked='checked']", count: 0

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot_one.id)

    assert_response :success
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='rock-alternative'][checked='checked']", count: 1
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='pop-mainstream'][checked='checked']", count: 0
    assert_select ".settings-reference-selection-index", text: "-", count: 2
  end

  test "homepage genre lanes section shows member genres as hover tooltip" do
    sign_in_as(@admin)
    snapshot = create_homepage_genre_snapshot(selected: true)
    snapshot.groups.find_by!(slug: "rock-alternative").update!(member_genres: [ "Rock", " Alternative ", "", "Rock" ])

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot.id)

    assert_response :success
    assert_select ".settings-reference-checkbox-copy[title='Enthaltene Genres: Alternative, Rock'] strong",
                  text: "Rock & Alternative",
                  count: 1
  end

  test "homepage genre lanes section renders copy buttons for member genres" do
    sign_in_as(@admin)
    snapshot = create_homepage_genre_snapshot(selected: true)
    snapshot.groups.find_by!(slug: "rock-alternative").update!(member_genres: [ "Rock", " Alternative ", "", "Rock" ])

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot.id)

    assert_response :success
    assert_select ".settings-reference-item-actions[data-controller='clipboard']", count: 2
    assert_select ".settings-reference-copy-button[aria-label='Genres von Rock & Alternative in Zwischenablage kopieren']",
                  count: 1
    assert_select ".settings-reference-copy-button svg", count: 2
    assert_select "[data-clipboard-target='source']", text: "Rock & Alternative: Alternative, Rock", count: 1
  end

  test "homepage genre lanes section renders copy button for distinct llm genres" do
    sign_in_as(@admin)
    snapshot = create_homepage_genre_snapshot(selected: true)

    first_event = Event.create!(
      slug: "homepage-genre-lanes-copy-source-1",
      source_fingerprint: "test::settings::homepage-genre-lanes-copy-source-1",
      title: "Homepage Genre Copy Source 1",
      artist_name: "Homepage Genre Copy Artist 1",
      start_at: 5.days.from_now.change(hour: 20),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    second_event = Event.create!(
      slug: "homepage-genre-lanes-copy-source-2",
      source_fingerprint: "test::settings::homepage-genre-lanes-copy-source-2",
      title: "Homepage Genre Copy Source 2",
      artist_name: "Homepage Genre Copy Artist 2",
      start_at: 6.days.from_now.change(hour: 20),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    EventLlmEnrichment.create!(
      event: first_event,
      source_run: import_runs(:one),
      genre: [ "Rock", " Alternative ", "", "Rock" ],
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )
    EventLlmEnrichment.create!(
      event: second_event,
      source_run: import_runs(:one),
      genre: [ "Pop", "Alternative" ],
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot.id)

    assert_response :success
    assert_select ".settings-group-header-actions[data-controller='clipboard'] .button",
                  text: "3 LLM-Genres kopieren",
                  count: 1
    assert_select ".settings-group-header-actions [data-clipboard-target='source']",
                  text: "Alternative, Pop, Rock",
                  count: 1
  end

  test "admin can enable similarity matching in settings" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :merge_artist_similarity_matching), params: {
      app_setting: {
        merge_artist_similarity_matching_enabled: "1"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :merge_artist_similarity_matching)
    assert_equal true, AppSetting.merge_artist_similarity_matching_enabled?
    assert_equal true, AppSetting.find_by!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).value
  end

  test "admin can update venue duplicate mappings" do
    sign_in_as(@admin)
    alias_venue = Venue.create!(
      name: "Liederhalle Beethovensaal",
      description: "Alias-Beschreibung",
      external_url: "https://alias.example",
      address: "Aliasstraße 1, 70173 Stuttgart"
    )

    patch backend_settings_url(section: :venue_duplicate_mappings), params: {
      app_setting: {
        venue_duplicate_mappings_text: <<~TEXT
          KKL Beethoven-Saal Stuttgart => Liederhalle Beethoven-Saal
          Liederhalle Beethovensaal => Liederhalle Beethoven-Saal
        TEXT
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :venue_duplicate_mappings)
    assert_equal [
      {
        "alias" => "KKL Beethoven-Saal Stuttgart",
        "canonical" => "Liederhalle Beethoven-Saal",
        "alias_key" => "kkl beethoven saal",
        "canonical_key" => "liederhalle beethoven saal"
      },
      {
        "alias" => "Liederhalle Beethovensaal",
        "canonical" => "Liederhalle Beethoven-Saal",
        "alias_key" => "liederhalle beethovensaal",
        "canonical_key" => "liederhalle beethoven saal"
      }
    ], AppSetting.venue_duplicate_mappings

    canonical = Venue.find_by_match_name("Liederhalle Beethoven-Saal")
    assert_predicate canonical, :present?
    assert_equal "Alias-Beschreibung", canonical.description
    assert_equal "https://alias.example", canonical.external_url
    assert_equal "Aliasstraße 1, 70173 Stuttgart", canonical.address
    assert_equal canonical, Venues::Resolver.call(name: alias_venue.name)
  end

  test "admin cannot save empty sks promoter ids" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :sks_promoter_ids), params: {
      app_setting: {
        sks_promoter_ids_text: " \n "
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-sks-promoter-ids[aria-selected='true']", count: 1
    assert_includes response.body, "muss mindestens eine Promoter-ID enthalten"
  end

  test "admin cannot save llm enrichment prompt without input placeholder" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-5.1",
        llm_enrichment_prompt_template_text: "Prompt ohne Platzhalter"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_includes response.body, "{{input_json}} muss im Prompt enthalten sein"
  end

  test "admin cannot save unsupported llm enrichment model" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-4.1",
        llm_enrichment_prompt_template_text: VALID_LLM_ENRICHMENT_PROMPT
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "ist kein unterstütztes LLM-Modell"
  end

  test "admin cannot save invalid llm enrichment temperature" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-5.1",
        llm_enrichment_prompt_template_text: VALID_LLM_ENRICHMENT_PROMPT,
        llm_enrichment_temperature: "2.5",
        llm_enrichment_web_search_provider: "serpapi"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_includes response.body, "muss eine Zahl zwischen 0 und 2 sein"
  end

  test "admin cannot save invalid llm genre grouping settings" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_genre_grouping), params: {
      app_setting: {
        llm_genre_grouping_model: "gpt-5-mini",
        llm_genre_grouping_prompt_template_text: "Gruppiere\n{{input_json}}",
        llm_genre_grouping_group_count: "0"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-llm-genre-grouping[aria-selected='true']", count: 1
    assert_includes response.body, "{{group_count}} muss im Prompt enthalten sein"
    assert_includes response.body, "muss eine positive Ganzzahl sein"
  end

  test "admin cannot save invalid venue duplicate mapping" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :venue_duplicate_mappings), params: {
      app_setting: {
        venue_duplicate_mappings_text: "KKL Beethoven-Saal Stuttgart"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-venue-duplicate-mappings[aria-selected='true']", count: 1
    assert_includes response.body, "muss das Format Alias =&gt; Kanonische Venue verwenden"
  end

  private

  def reset_settings!
    [
      AppSetting::SKS_PROMOTER_IDS_KEY,
      AppSetting::SKS_ORGANIZER_NOTES_KEY,
      AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY,
      AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY,
      AppSetting::LLM_ENRICHMENT_MODEL_KEY,
      AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      AppSetting::LLM_ENRICHMENT_TEMPERATURE_KEY,
      AppSetting::LLM_ENRICHMENT_WEB_SEARCH_PROVIDER_KEY,
      AppSetting::LLM_GENRE_GROUPING_MODEL_KEY,
      AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY,
      AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY,
      AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY,
      AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY
    ].each do |key|
      AppSetting.where(key: key).delete_all
    end

    AppSetting.reset_cache!
  end

  def create_facebook_connection_with_pages!
    SocialConnection.where(provider: "meta", platform: "facebook").destroy_all
    connection = SocialConnection.create!(
      provider: "meta",
      platform: "facebook",
      auth_mode: "facebook_login_for_business",
      connection_status: "connected",
      user_access_token: "user-token",
      user_token_expires_at: 40.days.from_now,
      granted_scopes: %w[pages_show_list pages_read_engagement pages_manage_posts]
    )
    connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "selected-page",
      name: "Selected Page",
      access_token: "selected-page-token",
      selected: true,
      status: "selected"
    )
    connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "other-page",
      name: "Other Page",
      access_token: "other-page-token",
      selected: false,
      status: "available"
    )
    connection
  end

  def create_instagram_connection!
    SocialConnection.where(provider: "meta", platform: "instagram").destroy_all
    connection = SocialConnection.create!(
      provider: "meta",
      platform: "instagram",
      auth_mode: "instagram_login",
      connection_status: "connected",
      user_access_token: "instagram-token",
      user_token_expires_at: 40.days.from_now,
      granted_scopes: %w[instagram_business_basic instagram_business_content_publish]
    )
    connection.social_connection_targets.create!(
      target_type: "instagram_account",
      external_id: "ig-123",
      username: "sl_test_26",
      selected: true,
      status: "selected"
    )
    connection
  end

  def with_stubbed_meta_connection_state(facebook_connection:, instagram_connection: nil)
    instagram_status = build_meta_access_status(
      connection_status: instagram_connection.present? ? "connected" : "disconnected",
      state: instagram_connection.present? ? :ok : :error,
      summary: instagram_connection.present? ? "Instagram-Verbindung ist gültig." : "Instagram fehlt.",
      instagram_username: instagram_connection&.selected_instagram_target&.username
    )
    facebook_status = build_meta_access_status(
      connection_status: "connected",
      state: :ok,
      summary: "Facebook-Verbindung ist gültig.",
      page_name: facebook_connection.selected_facebook_page_target.display_name
    )
    resolver = Object.new
    resolver.define_singleton_method(:instagram_connection) { instagram_connection }
    resolver.define_singleton_method(:facebook_connection) { facebook_connection }
    resolver.define_singleton_method(:connection_for) do |platform|
      case platform.to_s
      when "facebook" then facebook_connection
      when "instagram" then instagram_connection
      end
    end

    original_access_status_new = Meta::AccessStatus.method(:new)
    Meta::AccessStatus.define_singleton_method(:new) do |*_args, **kwargs|
      initialized_platform = kwargs[:platform].to_s
      service = Object.new
      service.define_singleton_method(:call) do |force: false, platform: nil|
        active_platform = platform.to_s.presence || initialized_platform
        active_platform == "facebook" ? facebook_status : instagram_status
      end
      service
    end

    with_singleton_return_value(Meta::ConnectionResolver, :new, resolver) { yield }
  ensure
    Meta::AccessStatus.define_singleton_method(:new, original_access_status_new) if original_access_status_new
  end

  def build_meta_access_status(connection_status:, state:, summary:, page_name: nil, instagram_username: nil)
    Meta::AccessStatus::Status.new(
      connection_status:,
      state:,
      summary:,
      details: [],
      checked_at: Time.current,
      expires_at: nil,
      page_name:,
      instagram_username:,
      permissions: [],
      debug_available: true,
      reauth_required: state == :error,
      payload: {}
    )
  end

  def page_target_row_for(facebook_card, title)
    facebook_card.css(".meta-page-target-row").find do |row|
      row.at_css(".social-post-card-title-row h4")&.text&.strip == title
    end
  end

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.define_singleton_method(method_name) { |*| value }
    yield
  ensure
    target.define_singleton_method(method_name, original_method)
  end

  def seed_all_settings!
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[10135 10136 382])
    AppSetting.create!(key: AppSetting::SKS_ORGANIZER_NOTES_KEY, value: "Bestehender Hinweistext")
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5-mini")
    AppSetting.new(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}").save!(validate: false)
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_TEMPERATURE_KEY, value: 1)
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_WEB_SEARCH_PROVIDER_KEY, value: "serpapi")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-5-mini")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY, value: "Gruppiere\n{{group_count}}\n{{input_json}}")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY, value: 30)
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: true)
    AppSetting.create!(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY, value: [])
    AppSetting.reset_cache!
  end

  def create_homepage_genre_snapshot(selected: false, lane_slugs: [])
    run = import_sources(:two).import_runs.create!(
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    snapshot = run.create_llm_genre_grouping_snapshot!(
      active: false,
      requested_group_count: 30,
      effective_group_count: 2,
      source_genres_count: 2,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    snapshot.groups.create!(position: 1, name: "Rock & Alternative", member_genres: [ "Rock" ])
    snapshot.groups.create!(position: 2, name: "Pop & Mainstream", member_genres: [ "Pop" ])
    snapshot.create_homepage_genre_lane_configuration!(lane_slugs:)
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: snapshot.id) if selected

    snapshot
  end
end

require "test_helper"

class Backend::ImportRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @source = import_sources(:one)
    @run = @source.import_runs.create!(
      status: "failed",
      source_type: "easyticket",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      metadata: {
        "filtered_out_cities" => [ "Berlin", "Stuttgart" ]
      }
    )
  end

  test "shows filtered out cities as clickable actions when missing in whitelist" do
    get backend_import_run_url(@run)
    assert_response :success

    assert_select "a[href='#{remove_whitelist_city_backend_import_run_path(@run, city: "Stuttgart")}']"
    assert_select "a[href='#{add_filtered_city_backend_import_run_path(@run, city: "Berlin")}']"
    assert_select "a[href='#{add_filtered_city_backend_import_run_path(@run, city: "Stuttgart")}']", count: 0
  end

  test "adds filtered city to import source whitelist and removes it from filtered list" do
    assert_not_includes @source.reload.configured_location_whitelist, "Berlin"
    assert_includes @run.reload.metadata.fetch("filtered_out_cities"), "Berlin"

    post add_filtered_city_backend_import_run_url(@run), params: { city: "Berlin" }

    assert_redirected_to backend_import_run_url(@run)
    assert_includes @source.reload.configured_location_whitelist, "Berlin"
    assert_not_includes @run.reload.metadata.fetch("filtered_out_cities"), "Berlin"
  end

  test "does not duplicate city in whitelist and removes it from filtered list" do
    config = @source.import_source_config || @source.build_import_source_config
    config.location_whitelist = @source.configured_location_whitelist + [ "Berlin" ]
    config.save!

    post add_filtered_city_backend_import_run_url(@run), params: { city: "Berlin" }

    assert_redirected_to backend_import_run_url(@run)
    occurrences = @source.reload.configured_location_whitelist.count { |entry| entry.casecmp?("Berlin") }
    assert_equal 1, occurrences
    assert_not_includes @run.reload.metadata.fetch("filtered_out_cities"), "Berlin"
  end

  test "rejects city that was not captured as filtered out" do
    previous_whitelist = @source.reload.configured_location_whitelist

    post add_filtered_city_backend_import_run_url(@run), params: { city: "Frankfurt" }

    assert_redirected_to backend_import_run_url(@run)
    assert_equal previous_whitelist, @source.reload.configured_location_whitelist
  end

  test "removes configured city from whitelist and adds it to filtered list" do
    assert_includes @source.reload.configured_location_whitelist, "Stuttgart"
    assert_includes @run.reload.metadata.fetch("filtered_out_cities"), "Stuttgart"

    post remove_whitelist_city_backend_import_run_url(@run), params: { city: "Stuttgart" }

    assert_redirected_to backend_import_run_url(@run)
    assert_not_includes @source.reload.configured_location_whitelist, "Stuttgart"
    assert_includes @run.reload.metadata.fetch("filtered_out_cities"), "Stuttgart"
  end

  test "rejects removing city that is not in whitelist" do
    previous_whitelist = @source.reload.configured_location_whitelist

    post remove_whitelist_city_backend_import_run_url(@run), params: { city: "Frankfurt" }

    assert_redirected_to backend_import_run_url(@run)
    assert_equal previous_whitelist, @source.reload.configured_location_whitelist
  end

  test "does not show city list sections for merge runs" do
    merge_run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "merge",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      metadata: { "filtered_out_cities" => [ "Berlin" ] }
    )

    get backend_import_run_url(merge_run)
    assert_response :success
    assert_not_includes response.body, "Ortsliste konfiguriert"
    assert_not_includes response.body, "Aussortierte Staedte"
  end

  test "shows merge raw imports groups and similarity duplicates on detail page" do
    merge_run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "merge",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      fetched_count: 5,
      imported_count: 5,
      upserted_count: 961,
      metadata: {
        "import_records_count" => 5,
        "groups_count" => 5,
        "events_created_count" => 1,
        "events_updated_count" => 4,
        "duplicate_matches_count" => 2,
        "offers_upserted_count" => 961
      }
    )

    get backend_import_run_url(merge_run)
    assert_response :success
    assert_select "table.data-table tbody tr td:nth-child(1) code", text: merge_run.id.to_s
    assert_select "table.data-table tbody tr td:nth-child(4)", text: "5"
    assert_select "table.data-table tbody tr td:nth-child(5)", text: "5"
    assert_select "table.data-table tbody tr td:nth-child(6)", text: "1"
    assert_select "table.data-table tbody tr td:nth-child(7)", text: "4"
    assert_select "table.data-table tbody tr td:nth-child(8)", text: "2"
    assert_select "table.data-table tbody tr td:nth-child(9)", text: "0"
  end

  test "shows source importer runs with raw imports and no merge-only metrics on detail page" do
    run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "easyticket",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      upserted_count: 3
    )

    get backend_import_run_url(run)
    assert_response :success
    assert_select "table.data-table tbody tr td:nth-child(1) code", text: run.id.to_s
    assert_select "table.data-table tbody tr td:nth-child(5)", text: "3"
    assert_select "table.data-table tbody tr td:nth-child(6)", text: "0"
    assert_select "table.data-table tbody tr td:nth-child(7)", text: "3"
  end

  test "shows llm run with dedicated columns on detail page" do
    run = import_sources(:two).import_runs.create!(
      status: "succeeded",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      fetched_count: 200,
      filtered_count: 25,
      imported_count: 140,
      failed_count: 3,
      metadata: { "batches_count" => 8 }
    )

    get backend_import_run_url(run)
    assert_response :success
    assert_select "table.data-table tbody tr td:nth-child(1) code", text: run.id.to_s
    assert_select "table.data-table tbody tr td:nth-child(4)", text: "200"
    assert_select "table.data-table tbody tr td:nth-child(5)", text: "25"
    assert_select "table.data-table tbody tr td:nth-child(6)", text: "140"
    assert_select "table.data-table tbody tr td:nth-child(7)", text: "8"
    assert_select "table.data-table tbody tr td:nth-child(8)", text: "3"
  end

  test "shows llm genre grouping run with snapshot details on detail page" do
    run = import_sources(:two).import_runs.create!(
      status: "succeeded",
      source_type: "llm_genre_grouping",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      fetched_count: 120,
      filtered_count: 3,
      imported_count: 30,
      upserted_count: 2,
      failed_count: 0,
      metadata: {
        "snapshot_key" => SecureRandom.uuid,
        "requested_group_count" => 30,
        "effective_group_count" => 30,
        "model" => "gpt-5-mini"
      }
    )
    snapshot = run.create_llm_genre_grouping_snapshot!(
      snapshot_key: SecureRandom.uuid,
      active: true,
      requested_group_count: 30,
      effective_group_count: 30,
      source_genres_count: 120,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )
    snapshot.groups.create!(position: 1, name: "Rock & Pop", member_genres: [ "Rock", "Pop" ])

    get backend_import_run_url(run)
    assert_response :success
    assert_select "table.data-table tbody tr td:nth-child(1) code", text: run.id.to_s
    assert_select "table.data-table tbody tr td:nth-child(4)", text: "120"
    assert_select "table.data-table tbody tr td:nth-child(5)", text: "3"
    assert_select "table.data-table tbody tr td:nth-child(6)", text: "30"
    assert_select "table.data-table tbody tr td:nth-child(7)", text: "2"
    assert_includes response.body, "Gruppierungs-Snapshot"
    assert_select "td", text: "Rock & Pop"
    assert_includes response.body, snapshot.snapshot_key
  end
end

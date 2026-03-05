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
      metadata: { "filtered_out_cities" => [ "Berlin", "Stuttgart" ] }
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

  test "shows merge upserts as created plus updated events on detail page" do
    merge_run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "merge",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      imported_count: 5,
      upserted_count: 961,
      metadata: {
        "events_created_count" => 1,
        "events_updated_count" => 4,
        "offers_upserted_count" => 961
      }
    )

    get backend_import_run_url(merge_run)
    assert_response :success
    assert_select "table.data-table tbody tr td:nth-child(6)", text: "5"
  end
end

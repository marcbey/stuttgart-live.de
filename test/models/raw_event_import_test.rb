require "test_helper"

class RawEventImportTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert raw_event_imports(:one).valid?
  end

  test "latest_for returns newest rows per source key as relation" do
    source = import_sources(:two)
    old_import = create_raw_import(source:, source_identifier: "shared", created_at: 3.days.ago)
    newest_import = create_raw_import(source:, source_identifier: "shared", created_at: 2.days.ago)
    other_import = create_raw_import(source:, source_identifier: "other", created_at: 1.day.ago)
    create_raw_import(
      source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "shared",
      created_at: 1.day.ago
    )

    latest_imports = RawEventImport.latest_for(RawEventImport.where(import_event_type: "eventim"))

    assert_kind_of ActiveRecord::Relation, latest_imports
    assert_equal [ newest_import.id, other_import.id ].sort, latest_imports.pluck(:id).sort
    assert_not_includes latest_imports.pluck(:id), old_import.id
    assert_equal 2, latest_imports.where(import_event_type: "eventim").count
  end

  private

  def create_raw_import(source:, source_identifier:, created_at:, import_event_type: "eventim")
    RawEventImport.create!(
      import_source: source,
      import_event_type: import_event_type,
      source_identifier: source_identifier,
      payload: { "event_id" => source_identifier, "title" => source_identifier },
      detail_payload: {},
      created_at: created_at,
      updated_at: created_at
    )
  end
end

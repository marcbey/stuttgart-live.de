require "test_helper"

class EventSeriesTest < ActiveSupport::TestCase
  test "validates imported series source fields" do
    series = EventSeries.new(origin: "imported")

    assert_not series.valid?
    assert series.errors[:source_type].present?
    assert series.errors[:source_key].present?
  end

  test "display_name falls back to a generic label" do
    series = EventSeries.create!(origin: "manual")

    assert_equal "Event-Reihe", series.display_name
  end
end

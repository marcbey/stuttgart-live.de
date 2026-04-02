require "test_helper"

class Public::Events::Search::TimePhraseResolverTest < ActiveSupport::TestCase
  test "resolves am wochenende to the upcoming weekend" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      resolution = resolve(type: :coming_weekend)

      assert_equal Time.zone.parse("2026-04-11 00:00:00"), resolution.from
      assert_equal Time.zone.parse("2026-04-12 23:59:59.999999999"), resolution.to
    end
  end

  test "resolves am wochenende to the current weekend on sunday" do
    travel_to(Time.zone.parse("2026-04-12 12:00:00")) do
      resolution = resolve(type: :coming_weekend)

      assert_equal Time.zone.parse("2026-04-11 00:00:00"), resolution.from
      assert_equal Time.zone.parse("2026-04-12 23:59:59.999999999"), resolution.to
    end
  end

  test "distinguishes dieses and nächstes wochenende" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      this_weekend = resolve(type: :this_weekend)
      next_weekend = resolve(type: :next_weekend)

      assert_equal Date.new(2026, 4, 11), this_weekend.from.to_date
      assert_equal Date.new(2026, 4, 18), next_weekend.from.to_date
    end
  end

  test "resolves übernächstes wochenende two weeks ahead" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      resolution = resolve(type: :week_after_next_weekend)

      assert_equal Date.new(2026, 4, 25), resolution.from.to_date
      assert_equal Date.new(2026, 4, 26), resolution.to.to_date
    end
  end

  test "resolves diese and nächste woche by calendar week" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      this_week = resolve(type: :this_week)
      next_week = resolve(type: :next_week)

      assert_equal Date.new(2026, 4, 6), this_week.from.to_date
      assert_equal Date.new(2026, 4, 12), this_week.to.to_date
      assert_equal Date.new(2026, 4, 13), next_week.from.to_date
      assert_equal Date.new(2026, 4, 19), next_week.to.to_date
    end
  end

  test "resolves current and next weekday" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      this_week = resolve(type: :this_weekday, value: :friday)
      next_week = resolve(type: :next_weekday, value: :friday)

      assert_equal Date.new(2026, 4, 10), this_week.from.to_date
      assert_equal Date.new(2026, 4, 17), next_week.from.to_date
    end
  end

  test "resolves month in current or next year" do
    travel_to(Time.zone.parse("2026-04-07 12:00:00")) do
      april = resolve(type: :month, value: :april)
      march = resolve(type: :month, value: :march)

      assert_equal Date.new(2026, 4, 1), april.from.to_date
      assert_equal Date.new(2027, 3, 1), march.from.to_date
    end
  end

  test "resolves nächsten monat to the next calendar month" do
    travel_to(Time.zone.parse("2026-12-20 12:00:00")) do
      resolution = resolve(type: :next_month)

      assert_equal Date.new(2027, 1, 1), resolution.from.to_date
      assert_equal Date.new(2027, 1, 31), resolution.to.to_date
    end
  end

  test "resolves diesen monat to the current calendar month" do
    travel_to(Time.zone.parse("2026-12-20 12:00:00")) do
      resolution = resolve(type: :this_month)

      assert_equal Date.new(2026, 12, 1), resolution.from.to_date
      assert_equal Date.new(2026, 12, 31), resolution.to.to_date
    end
  end

  test "resolves explicit dates with and without year" do
    travel_to(Time.zone.parse("2026-12-20 12:00:00")) do
      future_same_year = resolve(type: :date, value: "24.12.")
      next_year = resolve(type: :date, value: "1.4.")
      explicit_year = resolve(type: :date, value: "1.4.2028")

      assert_equal Date.new(2026, 12, 24), future_same_year.from.to_date
      assert_equal Date.new(2027, 4, 1), next_year.from.to_date
      assert_equal Date.new(2028, 4, 1), explicit_year.from.to_date
    end
  end

  private

  def resolve(type:, value: nil)
    Public::Events::Search::TimePhraseResolver.resolve(type:, value:)
  end
end

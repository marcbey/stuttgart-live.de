require "test_helper"

class Public::Events::Search::AnalyzerTest < ActiveSupport::TestCase
  test "parses complete static time phrases" do
    assert_equal :today, analyze("heute").resolution.type
    assert_equal :tomorrow, analyze("morgen").resolution.type
    assert_equal :day_after_tomorrow, analyze("übermorgen").resolution.type
    assert_equal :coming_weekend, analyze("am Wochenende").resolution.type
    assert_equal :this_week, analyze("diese Woche").resolution.type
    assert_equal :this_weekend, analyze("dieses Wochenende").resolution.type
    assert_equal :next_weekend, analyze("nächstes Wochenende").resolution.type
    assert_equal :week_after_next_weekend, analyze("übernächstes Wochenende").resolution.type
    assert_equal :next_week, analyze("nächste Woche").resolution.type
  end

  test "suggests weekday completions for abbreviated input" do
    result = analyze("diesen Mo")

    assert result.time_incomplete?
    assert_includes result.suggestions.map(&:label), "Diesen Montag"
  end

  test "resolves complete weekday phrases" do
    this_week = analyze("diesen Freitag")
    this_month = analyze("diesen Monat")
    next_week = analyze("nächsten Freitag")
    next_month = analyze("nächsten Monat")

    assert this_week.time_complete?
    assert_equal :this_weekday, this_week.resolution.type
    assert this_month.time_complete?
    assert_equal :this_month, this_month.resolution.type
    assert next_week.time_complete?
    assert_equal :next_weekday, next_week.resolution.type
    assert next_month.time_complete?
    assert_equal :next_month, next_month.resolution.type
  end

  test "suggests monat alongside montag for diesen m" do
    result = analyze("diesen m")

    assert result.time_incomplete?
    assert_includes result.suggestions.map(&:label), "Diesen Monat"
    assert_includes result.suggestions.map(&:label), "Diesen Montag"
  end

  test "suggests monat alongside montag for nächsten mon" do
    result = analyze("nächsten Mon")

    assert result.time_incomplete?
    assert_includes result.suggestions.map(&:label), "Nächsten Monat"
    assert_includes result.suggestions.map(&:label), "Nächsten Montag"
  end

  test "suggests month completions for abbreviated input" do
    result = analyze("im Apr")

    assert result.time_incomplete?
    assert_includes result.suggestions.map(&:label), "Im April"
  end

  test "resolves complete month and date phrases" do
    month = analyze("im April")
    date = analyze("am 1.4.2026")

    assert month.time_complete?
    assert_equal :month, month.resolution.type
    assert date.time_complete?
    assert_equal :date, date.resolution.type
  end

  test "parses structured queries with venue glue" do
    assert_equal [ :venue_fragment, "im", "wi" ], state_summary("heute im Wi")
    assert_equal [ :venue_fragment, "in", "wi" ], state_summary("heute in Wi")
    assert_equal [ :venue_fragment, "in der", "po" ], state_summary("morgen in der Po")
    assert_equal [ :venue_fragment, "in dem", "li" ], state_summary("übermorgen in dem Li")
    assert_equal [ :venue_fragment, "im", "goldmarks" ], state_summary("diese Woche im Goldmarks")
    assert_equal [ :venue_fragment, "im", "wi" ], state_summary("nächste Woche im Wi")
    assert_equal [ :venue_fragment, "im", "goldmarks" ], state_summary("diesen Monat im Goldmarks")
    assert_equal [ :venue_fragment, "im", "goldmarks" ], state_summary("nächsten Monat im Goldmarks")
    assert_equal [ :venue_fragment, "im", "goldmarks" ], state_summary("übernächstes Wochenende im Goldmarks")
    assert_equal [ :venue_fragment, "in der", "po" ], state_summary("diesen Freitag in der Po")
    assert_equal [ :venue_fragment, "in der", "po" ], state_summary("nächsten Freitag in der Po")
    assert_equal [ :venue_fragment, "im", "wi" ], state_summary("im April im Wi")
    assert_equal [ :venue_fragment, "in der", "wi" ], state_summary("im April in der Wi")
    assert_equal [ :venue_fragment, "im", "li" ], state_summary("am 1.4. im Li")
  end

  private

  def analyze(query)
    Public::Events::Search::Analyzer.call(query)
  end

  def state_summary(query)
    result = analyze(query)
    [ result.state, result.venue_glue, result.venue_query ]
  end
end

require "test_helper"

class Merging::ProviderPriorityMapTest < ActiveSupport::TestCase
  setup do
    Current.provider_priority_map = nil
  end

  teardown do
    Current.provider_priority_map = nil
  end

  test "returns import priorities from most to least important" do
    priorities = Merging::ProviderPriorityMap.call

    assert_equal 0, priorities["easyticket"]
    assert_equal 10, priorities["eventim"]
    assert_equal 20, priorities["reservix"]
    assert_operator priorities["easyticket"], :<, priorities["eventim"]
    assert_operator priorities["eventim"], :<, priorities["reservix"]
  end

  test "memoizes configured priorities in current request context" do
    queries = capture_sql_queries do
      2.times { Merging::ProviderPriorityMap.call }
    end

    provider_priority_queries = queries.count do |query|
      query.include?('"provider_priorities"')
    end

    assert_equal 1, provider_priority_queries
  end

  private

  def capture_sql_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end

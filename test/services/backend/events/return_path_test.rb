require "test_helper"

class Backend::Events::ReturnPathTest < ActiveSupport::TestCase
  test "keeps local paths with search filters and anchors" do
    path = "/search?q=Russ%20Live#events"

    assert_equal path, resolve(path)
    assert_equal path, resolve("http://localhost:3000#{path}")
  end

  test "rejects external origins and ambiguous redirect URLs" do
    [
      "https://example.org/events",
      "http://localhost:3001/events",
      "https://localhost:3000/events",
      "//example.org/events",
      "/%2fexample.org/events",
      "/\\example.org/events",
      "javascript:alert(1)",
      "/events%0d%0aLocation:example.org",
      "http://user@localhost:3000/events"
    ].each do |value|
      assert_nil resolve(value), value
    end
  end

  private

  def resolve(value)
    Backend::Events::ReturnPath.resolve(value, base_url: "http://localhost:3000")
  end
end

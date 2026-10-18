require "test_helper"

class SpoofedIpRequestsTest < ActionDispatch::IntegrationTest
  test "conflicting client IP headers are rejected as a bad request" do
    get "/errors/404", headers: {
      "HTTP_CLIENT_IP" => "198.51.100.10",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.20"
    }

    assert_response :bad_request
    assert_select "h1", text: "Diese Anfrage passt nicht."
    assert_not_includes response.body, "198.51.100.10"
  end

  test "matching client IP headers keep normal routing" do
    get "/errors/404", headers: {
      "HTTP_CLIENT_IP" => "198.51.100.10",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.10"
    }

    assert_response :not_found
  end

  test "conflicting client IP headers preserve an empty HEAD response" do
    head "/errors/404", headers: {
      "HTTP_CLIENT_IP" => "198.51.100.10",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.20"
    }

    assert_response :bad_request
    assert_empty response.body
  end

  test "forwarded IP without a client IP keeps normal routing" do
    get "/errors/404", headers: { "HTTP_X_FORWARDED_FOR" => "198.51.100.10, 172.18.0.2" }

    assert_response :not_found
  end

  test "conflicting client IP headers cannot create a login session" do
    assert_no_difference "Session.count" do
      post session_path, params: { email_address: "test@example.test", password: "invalid" }, headers: {
        "HTTP_CLIENT_IP" => "198.51.100.10",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.20"
      }
    end

    assert_response :bad_request
  end

  test "attacker body and query cannot select the rejection status" do
    post "/errors/500?code=500", params: { code: "500" }, headers: {
      "HTTP_CLIENT_IP" => "198.51.100.10",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.20"
    }

    assert_response :bad_request
    assert_select "h1", text: "Diese Anfrage passt nicht."
  end

  test "malformed JSON is not parsed while rejecting spoofed IP headers" do
    post session_path, params: "{invalid", headers: {
      "CONTENT_TYPE" => "application/json",
      "HTTP_CLIENT_IP" => "198.51.100.10",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.20"
    }

    assert_response :bad_request
    assert_select "h1", text: "Diese Anfrage passt nicht."
  end
end

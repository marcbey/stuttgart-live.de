require "rack/head"
require "stringio"

module RequestSecurity
  class IpSpoofingMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      ActionDispatch::Request.new(env).remote_ip
      @app.call(env)
    rescue ActionDispatch::RemoteIp::IpSpoofAttackError
      Rack::Head.new(ErrorsController.action(:show)).call(bad_request_env(env))
    end

    private

    def bad_request_env(env)
      env.except("RAW_POST_DATA", "rack.methodoverride.original_method")
        .reject { |key, _value| key.start_with?("action_dispatch.request.", "rack.request.") }
        .merge(
          "REQUEST_METHOD" => env["REQUEST_METHOD"] == "HEAD" ? "HEAD" : "GET",
          "PATH_INFO" => "/400", "QUERY_STRING" => "",
          "rack.input" => StringIO.new(""), "CONTENT_TYPE" => nil, "CONTENT_LENGTH" => "0",
          "action_dispatch.request.path_parameters" => { controller: "errors", action: "show", code: "400" },
          "action_dispatch.remote_ip" => env["REMOTE_ADDR"].to_s
        )
    end
  end
end

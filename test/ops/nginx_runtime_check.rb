# Mandatory post-build check: APP_IMAGE=... mise exec -- ruby test/ops/nginx_runtime_check.rb
require "minitest/autorun"
require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "securerandom"
require "tmpdir"
require "timeout"

class NginxRuntimeCheck < Minitest::Test
  IMAGE = ENV.fetch("APP_IMAGE")
  SECRET = "runtime-secret-1234567890"
  HTPASSWD = "tester:$6$runtime$ASgV/R6hSX6s0tdGMPY6lm1PZxWWgZM.qY6NKsxIRUmDjc6urwYTl.ptNuMCS5oUwvVLmAqoS2E7FtzGxh8Et."
  ENCODED_PATH = "/a%2Fb?q=%E2%82%AC&x=1+2"

  def setup
    @fixture = Dir.mktmpdir("nginx-runtime-")
    FileUtils.chmod(0o755, @fixture)
    FileUtils.mkdir_p(File.join(@fixture, "public/assets"))
    FileUtils.mkdir_p(File.join(@fixture, "storage/variants/check"))
    File.write(File.join(@fixture, "public/assets/runtime.css"), "body { color: red; }")
    File.write(File.join(@fixture, "public/sitemap.xml"), "<urlset/>")
    File.write(File.join(@fixture, "storage/variants/check/key"), "image-content")
    File.write(File.join(@fixture, "upstream.rb"), <<~'SERVER')
      require "socket"
      server = TCPServer.new("127.0.0.1", 3000)
      loop do
        client = server.accept
        line = client.gets
        next client.close unless line
        method, target = line.split(" ")
        headers = {}
        while (header = client.gets) && header != "\r\n"
          key, value = header.split(":", 2)
          headers[key.downcase] = value.strip
        end
        code = target.start_with?("/not-found") ? 404 : 200
        body = "#{method} #{target}"
        body = [ headers["x-request-start"], headers["x-request-id"] ].join("|") if target == "/timing"
        if target.split("?").first == "/up"
          code = Integer(ENV.fetch("TEST_UPSTREAM_HEALTH_CODE", "200"))
          body = code == 200 ? "ok\n" : "unavailable\n"
        end
        client.write("HTTP/1.1 #{code} Test\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    SERVER
  end

  def teardown
    Open3.capture2e("docker", "rm", "--force", @container) if @container
    Open3.capture2e("docker", "rm", "--force", @lock_holder) if @lock_holder
    Open3.capture2e("docker", "volume", "rm", @lock_volume) if @lock_volume
    FileUtils.remove_entry(@fixture)
  end

  def test_image_is_labeled_for_the_kamal_service
    expected = File.read(File.expand_path("../../config/deploy.yml", __dir__))[/^service:\s+(\w+)$/, 1]
    refute_nil expected
    assert_equal expected, docker!("image", "inspect", "--format", '{{ index .Config.Labels "service" }}', IMAGE).strip
  end

  def test_canonical_redirects_precede_assets_and_media_and_preserve_encoding
    start_nginx({ "CANONICAL_REDIRECT_ENABLED" => "true" })
    [ "www.app.example.invalid", "legacy.example.invalid" ].each do |host|
      [ ENCODED_PATH, "/assets/runtime.css?build=1", "/media/invalid/file.png?q=a%2Fb" ].each do |path|
        response = request(path, host:, method: "POST")
        assert_equal "308", response.code
        assert_equal "https://app.example.invalid#{path}", response["Location"]
      end
    end
    assert_equal "200", request("/").code
  end

  def test_redirects_remain_disabled_until_cutover
    start_nginx({ "CANONICAL_REDIRECT_ENABLED" => "false" })
    assert_equal "200", request("/", host: "legacy.example.invalid").code
  end

  def test_foreign_host_is_rejected_without_a_redirect
    start_nginx({ "CANONICAL_REDIRECT_ENABLED" => "true" })
    response = request(ENCODED_PATH, host: "foreign.example.invalid")
    assert_equal "421", response.code
    assert_nil response["Location"]
  end

  def test_staging_requires_authentication_before_every_content_and_error_response
    start_staging
    [ "/", "/assets/runtime.css", "/sitemap.xml", stable_media, "/media/invalid/file.png", "/not-found", "/up/", "/%75p" ].each do |path|
      response = request(path)
      assert_equal "401", response.code, path
      assert_equal "noindex, nofollow", response["X-Robots-Tag"], path
      assert_includes response["Cache-Control"], "no-store", path
    end
    assert_equal "401", request("/", password: "wrong").code
  end

  def test_authenticated_staging_serves_static_dynamic_and_signed_media_with_noindex
    start_staging
    [ "/", "/assets/runtime.css", "/sitemap.xml", stable_media, expiring_media ].each do |path|
      response = request(path, password: "stage-password")
      assert_equal "200", response.code, path
      assert_equal "noindex, nofollow", response["X-Robots-Tag"], path
      assert_includes response["Cache-Control"], "no-store", path
      assert_equal "image-content", response.body if path.start_with?("/media/")
    end
    response = request("/not-found", password: "stage-password")
    assert_equal "404", response.code
    assert_equal "noindex, nofollow", response["X-Robots-Tag"]
    response = request(stable_media(secret: "wrong-secret"), password: "stage-password")
    assert_equal "403", response.code
    assert_equal "noindex, nofollow", response["X-Robots-Tag"]
  end

  def test_exact_healthcheck_is_public_and_does_not_expose_application_data
    start_staging
    response = request("/up", host: "46.225.224.194")
    assert_equal "200", response.code
    assert_equal "ok\n", response.body
    assert_equal "noindex, nofollow", response["X-Robots-Tag"]
  end

  def test_staging_refuses_to_start_without_an_authentication_hash
    start_staging({ "STAGING_BASIC_AUTH_HTPASSWD" => "" }, expect_failure: true)
    assert_equal "exited", docker!("inspect", "--format", "{{.State.Status}}", @container).strip
  end

  def test_healthcheck_does_not_claim_success_when_puma_is_unhealthy
    start_nginx({ "TEST_UPSTREAM_HEALTH_CODE" => "503" })
    assert_equal "503", request("/up").code
  end

  def test_image_uid_can_share_and_exclude_public_image_work_on_a_named_volume
    @lock_volume = "codex-lock-check-#{SecureRandom.hex(5)}"
    @lock_holder = "codex-lock-holder-#{SecureRandom.hex(5)}"
    docker!("volume", "create", @lock_volume)
    mount = "#{@lock_volume}:/rails/public-image-lock"
    holder = 'File.open("/rails/public-image-lock/work.lock", "w") { |f| f.flock(File::LOCK_EX); File.write("/rails/public-image-lock/ready", Process.uid); sleep 60 }'
    docker!("run", "--detach", "--name", @lock_holder, "--volume", mount, "--entrypoint", "ruby", IMAGE, "-e", holder)
    ready = false
    40.times do
      _, status = Open3.capture2e("docker", "exec", @lock_holder, "test", "-f", "/rails/public-image-lock/ready")
      ready = status.success?
      break if ready
      sleep 0.1
    end
    assert ready, "UID 1000 cannot open the shared lock volume"
    assert_equal "1000", docker!("exec", @lock_holder, "cat", "/rails/public-image-lock/ready").strip
    attempt = 'File.open("/rails/public-image-lock/work.lock", "w") { |f| puts(f.flock(File::LOCK_EX | File::LOCK_NB) ? "acquired" : "busy") }'
    assert_equal "busy", docker!("run", "--rm", "--volume", mount, "--entrypoint", "ruby", IMAGE, "-e", attempt).strip
    docker!("rm", "--force", @lock_holder)
    @lock_holder = nil
    assert_equal "acquired", docker!("run", "--rm", "--volume", mount, "--entrypoint", "ruby", IMAGE, "-e", attempt).strip
  end

  def test_puma_stats_are_only_available_on_a_restricted_data_only_unix_socket
    start_nginx
    File.write(File.join(@fixture, "config.ru"), 'run ->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] }')
    docker!("exec", "--detach", "--env", "PUMA_CONTROL_ENABLED=true", "--env", "PORT=3001", "--env", "WEB_CONCURRENCY=2",
      @container, "/bin/bash", "-c", "bundle exec puma -C config/puma.rb /runtime-fixture/config.ru > /tmp/test-puma.log 2>&1")
    socket = "/rails/tmp/puma-control/stats.sock"
    result = nil
    40.times do
      result, status = Open3.capture2e("docker", "exec", @container, "curl", "--silent", "--fail", "--unix-socket", socket, "http://localhost/stats")
      break if status.success? && JSON.parse(result)["booted_workers"] == 2
      sleep 0.1
    end
    assert result.start_with?("{"), "Puma stats socket is unavailable"
    assert_equal 2, JSON.parse(result).fetch("booted_workers")
    assert_equal "700", docker!("exec", @container, "stat", "-c", "%a", "/rails/tmp/puma-control").strip
    assert_equal "700", docker!("exec", @container, "stat", "-c", "%a", socket).strip
    assert_equal "404", docker!("exec", @container, "curl", "--silent", "--output", "/dev/null", "--write-out", "%{http_code}",
      "--unix-socket", socket, "http://localhost/stop").strip
  end

  def test_proxy_overwrites_spoofed_timing_and_correlation_headers
    start_nginx
    response = request("/timing", headers: { "X-Request-Start" => "spoofed", "X-Request-Id" => "secret-id" })
    timestamp, id = response.body.split("|")
    assert_match(/\A\d{10}\.\d{3}\z/, timestamp)
    assert_in_delta Time.now.to_f, Float(timestamp), 3
    assert_match(/\A[0-9a-f]{32}\z/, id)
  end

  def test_nonessential_crawlers_have_a_shared_dynamic_budget_with_recovery
    start_nginx
    codes = 10.times.map do |index|
      request("/events/example", headers: { "User-Agent" => index.even? ? "GPTBot/1.0" : "AhrefsBot/7.0" })
    end
    assert codes.any? { |response| response.code == "200" }
    limited = codes.select { |response| response.code == "429" }
    assert_operator limited.length, :>=, 4
    assert limited.all? { |response| response["Retry-After"] == "2" }
    refute_includes docker!("logs", @container), "limiting requests"
    [ "Mozilla/5.0", "Googlebot/2.1", "bingbot/2.0", "Claude-SearchBot/1.0", "OAI-SearchBot/1.0", "ChatGPT-User/1.0", "facebookexternalhit/1.1", "NotGPTBot/1.0", "GPTBotSpoof/1.0" ].each do |agent|
      assert_equal "200", request("/events/example", headers: { "User-Agent" => agent }).code, agent
    end
    [ "/assets/runtime.css", stable_media, "/up" ].each do |path|
      assert_equal "200", request(path, headers: { "User-Agent" => "GPTBot/1.0" }).code, path
    end
    sleep 2
    assert_equal "200", request("/events/example", headers: { "User-Agent" => "GPTBot/1.0" }).code
  end

  def test_crawler_rejections_preserve_the_legacy_indexing_mode
    start_nginx({ "STAGING_NOINDEX" => "true" })
    limited = 8.times.map { request("/events/example", headers: { "User-Agent" => "GPTBot/1.0" }) }.find { |response| response.code == "429" }
    refute_nil limited
    assert_equal "noindex, nofollow", limited["X-Robots-Tag"]
  end

  def test_private_staging_auth_precedes_any_crawler_budget
    start_staging
    8.times do
      assert_equal "401", request("/events/example", headers: { "User-Agent" => "GPTBot/1.0" }).code
      assert_equal "200", request("/events/example", password: "stage-password", headers: { "User-Agent" => "GPTBot/1.0" }).code
    end
  end

  def test_access_logs_have_timings_and_fixed_routes_without_sensitive_request_data
    start_nginx
    request("/passwords/reset-secret/edit?token=query-secret", headers: { "User-Agent" => "ua-secret", "Cookie" => "cookie-secret", "X-Request-Id" => "id-secret" })
    request(stable_media)
    output = docker!("logs", @container)
    refute_match(/reset-secret|query-secret|ua-secret|cookie-secret|id-secret/, output)
    rows = output.lines.filter_map { |line| JSON.parse(line) if line.start_with?("{") }
    row = rows.find { |entry| entry["route"] == "/passwords/*" }
    refute_nil row
    assert_match(/\A[0-9a-f]{32}\z/, row.fetch("request_id"))
    assert_operator Float(row.fetch("request_s")), :>=, 0
    assert_operator Float(row.fetch("upstream_s")), :>=, 0
    assert rows.any? { |entry| entry["route"] == "/media/*" }
  end

  private

  def start_staging(overrides = {}, expect_failure: false)
    start_nginx({ "APP_ENVIRONMENT" => "staging", "STAGING_NOINDEX" => "false", "STAGING_BASIC_AUTH_HTPASSWD" => HTPASSWD }.merge(overrides), expect_failure:)
  end

  def start_nginx(overrides = {}, expect_failure: false)
    @container = "codex-nginx-check-#{SecureRandom.hex(5)}"
    env = { "APP_ENVIRONMENT" => "production", "APP_HOST" => "app.example.invalid", "APP_ALLOWED_HOSTS" => "app.example.invalid,www.app.example.invalid,legacy.example.invalid",
      "CANONICAL_REDIRECT_ENABLED" => "false", "MEDIA_PROXY_SECRET" => SECRET, "STAGING_NOINDEX" => "false" }.merge(overrides)
    boot = <<~'SHELL'
      set -euo pipefail
      mkdir -p /tmp/nginx/{client_body,proxy,fastcgi,uwsgi,scgi,denied-media}
      if [ -x /rails/bin/render-nginx-config ]; then
        /rails/bin/render-nginx-config
      else
        # Compatibility harness for the existing image's renderer, before extraction.
        export STAGING_NOINDEX_HEADER=''
        if [ "${STAGING_NOINDEX:-}" = true ]; then
          export STAGING_NOINDEX_HEADER='add_header X-Robots-Tag "noindex, nofollow" always;'
        fi
        envsubst '${MEDIA_PROXY_SECRET} ${STAGING_NOINDEX_HEADER}' < /rails/config/nginx.conf.template > /tmp/nginx.conf
      fi
      nginx -t -c /tmp/nginx.conf
      ruby /runtime-fixture/upstream.rb &
      exec nginx -c /tmp/nginx.conf -g 'daemon off;'
    SHELL
    env_args = env.flat_map { |key, value| [ "--env", "#{key}=#{value}" ] }
    docker!("run", "--detach", "--name", @container, "--publish", "127.0.0.1::80", "--entrypoint", "/bin/bash",
      "--volume", "#{@fixture}:/runtime-fixture:ro", "--volume", "#{@fixture}/public:/rails/public:ro",
      "--volume", "#{@fixture}/storage:/rails/storage:ro", *env_args, IMAGE, "-c", boot)
    @port = nil
    Timeout.timeout(20) do
      loop do
        state = docker!("inspect", "--format", "{{.State.Status}}", @container).strip
        if state == "exited"
          return if expect_failure
          flunk docker!("logs", @container)
        end
        unless expect_failure
          ports = JSON.parse(docker!("inspect", "--format", "{{json .NetworkSettings.Ports}}", @container))
          @port = Integer(ports.fetch("80/tcp").first.fetch("HostPort"))
          begin
            ready = request("/runtime-ready", password: (env["APP_ENVIRONMENT"] == "staging" ? "stage-password" : nil))
            return if ready.code == "200" && ready.body == "GET /runtime-ready"
          rescue Errno::ECONNREFUSED, EOFError, Errno::ECONNRESET
            # Wait only for this isolated test server to accept requests.
          end
        end
        sleep 0.1
      end
    end
  rescue Timeout::Error
    flunk "nginx startup did not reach expected state: #{docker!('logs', @container)}"
  end

  def request(path, host: "app.example.invalid", method: "GET", password: nil, headers: {})
    message = method == "POST" ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    headers.each { |key, value| message[key] = value }
    message["Host"] = host
    message.basic_auth("tester", password) if password
    Net::HTTP.start("127.0.0.1", @port, open_timeout: 3, read_timeout: 3) { |http| http.request(message) }
  end

  def stable_media(secret: SECRET)
    path = "variants/check/key"
    signature = Base64.urlsafe_encode64(Digest::MD5.digest("#{path}#{secret}"), padding: false)
    "/media/#{signature}/#{path}/sample.png"
  end

  def expiring_media
    expires = Time.now.to_i + 3600
    path = "variants/check/key"
    signature = Base64.urlsafe_encode64(Digest::MD5.digest("#{expires}/#{path}#{SECRET}"), padding: false)
    "/media/#{expires}/#{signature}/#{path}--sample.png"
  end

  def docker!(*args)
    output, status = Open3.capture2e("docker", *args)
    raise "Docker command failed: #{output}" unless status.success?
    output
  end
end

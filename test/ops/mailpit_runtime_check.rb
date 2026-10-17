# Run explicitly: mise exec -- bundle exec ruby test/ops/mailpit_runtime_check.rb
require "bundler/setup"
require "kamal"
require "active_support/core_ext/hash/deep_merge"
require "active_support/core_ext/object/blank"
require "json"
require "net/http"
require "net/smtp"
require "open3"
require "securerandom"
require "timeout"

root = Pathname.new(__dir__).join("../..").expand_path
Dir.chdir(root)
ENV["KAMAL_DESTINATION"] = "staging"
config = Kamal::Configuration.load_raw_config(config_file: root.join("config/deploy.yml"), destination: "staging")
Kamal::Configuration.new(config, destination: "staging")
mailpit = config.fetch(:accessories).fetch("mailpit")
raise "Mailpit UI must bind to host loopback" unless mailpit.fetch("port") == "127.0.0.1:8025:8025"
raise "Mailpit image must be digest pinned" unless mailpit.fetch("image").match?(/\Aaxllent\/mailpit:v[\d.]+@sha256:[a-f0-9]{64}\z/)
mailpit_env = mailpit.fetch("env").fetch("clear")
raise "External relay must not be configured" if mailpit_env.keys.any? { |key| key.include?("RELAY") || key.include?("FORWARD") }
raise "Mail retention must be at most 1000 messages" unless (1..1000).cover?(Integer(mailpit_env.fetch("MP_MAX_MESSAGES")))
raise "Memory limit must stay 128m" unless mailpit.fetch("options").fetch("memory") == "128m"

container = "codex-mailpit-check-#{SecureRandom.hex(5)}"
def docker!(*args)
  output, status = Open3.capture2e("docker", *args)
  raise "Docker command failed: #{output}" unless status.success?
  output
end

begin
  env_args = mailpit_env.flat_map { |key, value| [ "--env", "#{key}=#{value}" ] }
  docker!("run", "--detach", "--rm", "--name", container, "--memory", "128m", "--cpus", "0.1",
    "--publish", "127.0.0.1::1025", "--publish", "127.0.0.1::8025", *env_args, mailpit.fetch("image"))
  ports = JSON.parse(docker!("inspect", "--format", "{{json .NetworkSettings.Ports}}", container))
  bindings = ports.fetch("1025/tcp") + ports.fetch("8025/tcp")
  raise "Test ports escaped loopback" unless bindings.all? { |binding| binding.fetch("HostIp") == "127.0.0.1" }
  smtp_port = Integer(ports.fetch("1025/tcp").first.fetch("HostPort"))
  http_port = Integer(ports.fetch("8025/tcp").first.fetch("HostPort"))
  base = "http://127.0.0.1:#{http_port}"
  Timeout.timeout(20) do
    loop do
      begin
        break if Net::HTTP.get_response(URI("#{base}/api/v1/info")).is_a?(Net::HTTPSuccess)
      rescue Errno::ECONNREFUSED, EOFError, Errno::ECONNRESET
        # Only the freshly started disposable local container is retried.
      end
      sleep 0.1
    end
  end
  Net::SMTP.start("127.0.0.1", smtp_port) do |smtp|
    smtp.send_message("From: stage@example.invalid\r\nTo: recipient@example.invalid\r\nSubject: Staging SMTP check\r\n\r\nCaptured locally.\r\n",
      "stage@example.invalid", "recipient@example.invalid")
  end
  messages = JSON.parse(Net::HTTP.get(URI("#{base}/api/v1/messages")))
  raise "SMTP message was not captured" unless messages.fetch("messages").any? { |message| message.fetch("Subject") == "Staging SMTP check" }
  raise "Mailpit UI unavailable" unless Net::HTTP.get_response(URI(base)).is_a?(Net::HTTPSuccess)
  puts "Mailpit runtime passed: SMTP captured, UI on loopback, pinned image, no relay configuration."
ensure
  Open3.capture2e("docker", "rm", "--force", container)
end

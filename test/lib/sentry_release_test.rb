require "test_helper"
require "open3"

class SentryReleaseTest < ActiveSupport::TestCase
  test "staging release command uses staging and rejects a conflicting destination" do
    Dir.mktmpdir do |dir|
      executable = File.join(dir, "sentry-cli")
      log = File.join(dir, "calls.log")
      File.write(executable, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SENTRY_TEST_LOG\"\n")
      FileUtils.chmod(0o700, executable)
      env = { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "SENTRY_TEST_LOG" => log,
        "SENTRY_AUTH_TOKEN" => "test-token", "APP_ENVIRONMENT" => "staging", "SENTRY_ENVIRONMENT" => nil }
      command = [ "bash", Rails.root.join("bin/sentry-release").to_s, "--release", "test-release", "--dotenv", File.join(dir, "missing.env") ]
      output, status = Open3.capture2e(env, *command)
      assert status.success?, output
      assert_includes File.read(log), "releases deploys test-release new -e staging"
      assert_includes File.read(log), "releases set-commits --auto test-release"
      FileUtils.rm_f(log)
      output, status = Open3.capture2e(env.merge("SENTRY_COMMIT_REFERENCE" => "marcbey/stuttgart-live.de@#{'a' * 40}"), *command)
      assert status.success?, output
      assert_includes File.read(log), "releases set-commits --commit marcbey/stuttgart-live.de@#{'a' * 40} test-release"
      refute_includes File.read(log), "--auto"
      FileUtils.rm_f(log)
      output, status = Open3.capture2e(env, *command, "--environment", "production")
      refute status.success?
      assert_includes output, "Staging-Releases"
      refute File.exist?(log)
    end
  end
end

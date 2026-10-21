# Run using bin/ci
require "shellwords"

rails_test_command = "env BULLET=1 bin/rails test"
if ENV["LOCAL_DESIGN_CHECKS"] == "1"
  unless ENV["CI"].to_s.empty? && ENV["GITHUB_ACTIONS"].to_s.empty?
    raise "LOCAL_DESIGN_CHECKS ist nur lokal erlaubt, nicht in CI."
  end

  excluded_tests = %w[
    test/lib/hetzner_check_test.rb
    test/lib/compatibility_copy_test.rb
    test/services/staging/data_sanitizer_test.rb
  ]
  test_files = Dir["test/**/*_test.rb"].reject do |path|
    path.start_with?("test/system/") || excluded_tests.include?(path)
  end.sort
  puts "Lokaler Design-Check: Ausgenommen sind #{excluded_tests.join(', ')}"
  rails_test_command = Shellwords.join([ "env", "BULLET=1", "bin/rails", "test", *test_files ])
end

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: JavaScript vulnerability audit", "bun audit --audit-level=high"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: JavaScript and performance parsers", "node --test test/javascript/*_test.mjs"
  step "Tests: Rails (Bullet)", rails_test_command
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end

require "test_helper"
require "shellwords"

class LocalCiProfileTest < ActiveSupport::TestCase
  class Recorder
    attr_reader :steps

    def initialize
      @steps = {}
    end

    def run(&block)
      instance_eval(&block)
    end

    def step(name, command)
      steps[name] = command
    end
  end

  test "default profile keeps the complete Rails suite" do
    with_profile_env do
      assert_equal "env BULLET=1 bin/rails test", recorded_steps.fetch("Tests: Rails (Bullet)")
    end
  end

  test "local design profile excludes only the three approved infrastructure files" do
    with_profile_env("LOCAL_DESIGN_CHECKS" => "1") do
      steps = recorded_steps
      files = Shellwords.split(steps.fetch("Tests: Rails (Bullet)")).drop(4)
      standard_files = Dir["test/**/*_test.rb"].reject { |path| path.start_with?("test/system/") }

      assert_equal %w[
        test/lib/compatibility_copy_test.rb
        test/lib/hetzner_check_test.rb
        test/services/staging/data_sanitizer_test.rb
      ], (standard_files - files).sort
      assert_includes files, "test/controllers/public/query_loading_test.rb"
      assert_equal "env RAILS_ENV=test bin/rails db:seed:replant", steps.fetch("Tests: Seeds")
      assert steps.key?("Security: Brakeman code analysis")
    end
  end

  test "CI and GitHub Actions reject local exclusions before executing checks" do
    %w[CI GITHUB_ACTIONS].each do |key|
      with_profile_env("LOCAL_DESIGN_CHECKS" => "1", key => "true") do
        error = assert_raises(RuntimeError) { recorded_steps }
        assert_match(/nur lokal/, error.message)
      end
    end
  end

  private

  def recorded_steps
    recorder = Recorder.new
    scope = Module.new
    scope.const_set(:CI, recorder)
    path = Rails.root.join("config/ci.rb")
    scope.module_eval(File.read(path), path.to_s)
    recorder.steps
  end

  def with_profile_env(values = {})
    keys = %w[LOCAL_DESIGN_CHECKS CI GITHUB_ACTIONS]
    previous = ENV.to_h.slice(*keys)
    keys.each { |key| ENV.delete(key) }
    ENV.update(values)
    yield
  ensure
    keys.each { |key| ENV.delete(key) }
    ENV.update(previous)
  end
end

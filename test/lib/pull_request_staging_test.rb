require "test_helper"

class PullRequestStagingTest < ActiveSupport::TestCase
  setup do
    path = Rails.root.join("script/ops/pull_request_staging.rb")
    assert_path_exists path
    require path
    @selection = { pr_number: 158, commit: "a" * 40, ci_run_id: 123 }
    @digest = "sha256:#{'b' * 64}"
    @operations = []
    operations = @operations
    @source = Object.new
    @source.define_singleton_method(:validate!) { |**| operations << :validated }
    @deployment = Object.new
    @deployment.define_singleton_method(:destination) { "staging" }
    @deployment.define_singleton_method(:with_lock) do |&block|
      operations << :locked
      block.call
      operations << :released
    end
    @deployment.define_singleton_method(:deploy!) { |**arguments| operations << arguments }
    @deployment.define_singleton_method(:smoke_peer!) { operations << :peer_checked }
    @deployment.define_singleton_method(:notify_sentry!) { |commit:| operations << { sentry_commit: commit } }
  end

  test "PR staging revalidates under the shared lock and deploys the pinned image using trusted controls" do
    Ops::PullRequestStaging.call(deployment: @deployment, source: @source, selection: @selection, digest: @digest, checkout_commit: "c" * 40)

    assert_equal [ :locked, :validated, { commit: "a" * 40, digest: "sha256:#{'b' * 64}", checkout_commit: "c" * 40 },
      :peer_checked, { sentry_commit: "a" * 40 }, :released ], @operations
  end

  test "stale or closed PR and replaced image refusals release the host lock before any deployment" do
    @source.define_singleton_method(:validate!) { |**| raise Ops::ReleaseSupport::Error, "PR changed" }

    assert_raises(Ops::ReleaseSupport::Error) do
      Ops::PullRequestStaging.call(deployment: @deployment, source: @source, selection: @selection, digest: @digest, checkout_commit: "c" * 40)
    end
    assert_equal [ :locked, :released ], @operations
  end

  test "PR deployment cannot target production" do
    @deployment.define_singleton_method(:destination) { "hetzner" }

    assert_raises(Ops::ReleaseSupport::Error) do
      Ops::PullRequestStaging.call(deployment: @deployment, source: @source, selection: @selection, digest: @digest, checkout_commit: "c" * 40)
    end
    assert_empty @operations
  end

  test "a failed deployment keeps the existing operation fence and cannot report success" do
    @deployment.define_singleton_method(:deploy!) { |**| raise Ops::ReleaseSupport::Error, "Deploy failed" }

    assert_raises(Ops::ReleaseSupport::Error) do
      Ops::PullRequestStaging.call(deployment: @deployment, source: @source, selection: @selection, digest: @digest, checkout_commit: "c" * 40)
    end
    assert_equal [ :locked, :validated ], @operations
  end
end

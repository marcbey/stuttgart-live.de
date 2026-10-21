require "test_helper"

class PullRequestSourceTest < ActiveSupport::TestCase
  REPOSITORY = "marcbey/stuttgart-live.de".freeze
  COMMIT = ("a" * 40).freeze

  setup do
    path = Rails.root.join("script/ops/pull_request_source.rb")
    assert_path_exists path
    require path
    @pull = {
      "number" => 158, "state" => "open", "merged" => false,
      "head" => { "sha" => COMMIT, "ref" => "feature/preview", "repo" => { "id" => 42, "full_name" => REPOSITORY } },
      "base" => { "ref" => "main", "repo" => { "id" => 42, "full_name" => REPOSITORY } }
    }
    @run = {
      "id" => 123, "status" => "completed", "conclusion" => "success", "event" => "pull_request",
      "path" => ".github/workflows/ci.yml", "head_sha" => COMMIT, "head_branch" => "feature/preview",
      "repository" => { "id" => 42, "full_name" => REPOSITORY },
      "head_repository" => { "id" => 42, "full_name" => REPOSITORY },
      "pull_requests" => [ { "number" => 158, "head" => { "sha" => COMMIT, "repo" => { "id" => 42 } },
        "base" => { "ref" => "main", "repo" => { "id" => 42 } } } ]
    }
    @responses = {
      "repos/#{REPOSITORY}/pulls/158" => @pull,
      "repos/#{REPOSITORY}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=#{COMMIT}&branch=feature%2Fpreview&per_page=1" => { "workflow_runs" => [ @run ] }
    }
    responses = @responses
    @api = Object.new
    @api.define_singleton_method(:github_json) { |path| responses.fetch(path) }
    @api.define_singleton_method(:registry_digest) { |**| "sha256:#{'b' * 64}" }
    @source = Ops::PullRequestSource.new(repository: REPOSITORY, api: @api)
  end

  test "the current open own PR with a successful latest CI exports a pinned selection" do
    assert_equal({ pr_number: 158, commit: COMMIT, ci_run_id: 123 }, @source.resolve(pr_number: "158"))
  end

  test "dispatch requires main and a numeric PR number from the own repository" do
    event = { "repository" => { "full_name" => REPOSITORY }, "inputs" => { "pr_number" => "158" } }
    assert_equal 158, Ops::PullRequestSource.dispatch_number(repository: REPOSITORY, event_name: "workflow_dispatch", ref: "refs/heads/main", event:)
    [ [ "pull_request", "refs/heads/main", event ], [ "workflow_dispatch", "refs/heads/feature", event ],
      [ "workflow_dispatch", "refs/heads/main", event.merge("repository" => { "full_name" => "other/repo" }) ] ].each do |name, ref, payload|
      assert_raises(Ops::ReleaseSupport::Error) do
        Ops::PullRequestSource.dispatch_number(repository: REPOSITORY, event_name: name, ref:, event: payload)
      end
    end
    [ "", "0", "-1", "158\ninjected=true", "158;echo bad" ].each do |number|
      assert_raises(Ops::ReleaseSupport::Error) { @source.resolve(pr_number: number) }
    end
  end

  test "closed merged foreign forked or non-main pull requests are rejected" do
    mutations = [
      ->(pull) { pull["state"] = "closed" }, ->(pull) { pull["merged"] = true },
      ->(pull) { pull["number"] = 159 }, ->(pull) { pull["base"]["ref"] = "other" },
      ->(pull) { pull["head"]["repo"]["id"] = 99 },
      ->(pull) { pull["head"]["repo"]["full_name"] = "other/repo" },
      ->(pull) { pull["base"]["repo"]["full_name"] = "other/repo" },
      ->(pull) { pull["head"]["sha"] = "bad\ninjected=true" }
    ]
    original = Marshal.dump(@pull)
    mutations.each do |mutate|
      @pull.replace(Marshal.load(original))
      mutate.call(@pull)
      assert_raises(Ops::ReleaseSupport::Error) { @source.resolve(pr_number: 158) }
    end
  end

  test "missing unsuccessful running stale foreign or unrelated CI never authorizes deployment" do
    mutations = [
      ->(run) { run["status"] = "in_progress" }, ->(run) { run["conclusion"] = "failure" },
      ->(run) { run["conclusion"] = "cancelled" }, ->(run) { run["event"] = "push" },
      ->(run) { run["path"] = ".github/workflows/other.yml" }, ->(run) { run["head_sha"] = "c" * 40 },
      ->(run) { run["head_branch"] = "other" }, ->(run) { run["id"] = 0 },
      ->(run) { run["repository"]["full_name"] = "other/repo" },
      ->(run) { run["head_repository"]["id"] = 99 }, ->(run) { run["pull_requests"] = [] },
      ->(run) { run["pull_requests"][0]["number"] = 159 },
      ->(run) { run["pull_requests"][0]["head"]["sha"] = "c" * 40 }
    ]
    original = Marshal.dump(@run)
    mutations.each do |mutate|
      @run.replace(Marshal.load(original))
      mutate.call(@run)
      assert_raises(Ops::ReleaseSupport::Error) { @source.resolve(pr_number: 158) }
    end
    @responses.values.last["workflow_runs"] = []
    assert_raises(Ops::ReleaseSupport::Error) { @source.resolve(pr_number: 158) }
  end

  test "deploy validation binds the selected PR commit CI run and registry digest" do
    selection = { pr_number: 158, commit: COMMIT, ci_run_id: 123 }
    assert @source.validate!(selection:, digest: "sha256:#{'b' * 64}")
    assert_raises(Ops::ReleaseSupport::Error) { @source.validate!(selection: selection.merge(commit: "c" * 40), digest: "sha256:#{'b' * 64}") }
    assert_raises(Ops::ReleaseSupport::Error) { @source.validate!(selection: selection.merge(ci_run_id: 122), digest: "sha256:#{'b' * 64}") }
    assert_raises(Ops::ReleaseSupport::Error) { @source.validate!(selection:, digest: "sha256:#{'c' * 64}") }
    @pull["state"] = "closed"
    assert_raises(Ops::ReleaseSupport::Error) { @source.validate!(selection:, digest: "sha256:#{'b' * 64}") }
  end
end

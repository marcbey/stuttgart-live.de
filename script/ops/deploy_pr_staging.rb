require_relative "deploy_release"
require_relative "pull_request_staging"

begin
  repository = Ops::ReleaseSupport.repository
  number = Ops::PullRequestSource.dispatch_number(repository:, event_name: ENV.fetch("GITHUB_EVENT_NAME"), ref: ENV.fetch("GITHUB_REF"),
    event: JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))))
  selection = { pr_number: number, commit: ENV.fetch("RELEASE_COMMIT"), ci_run_id: Ops::ReleaseSupport.run_id(ENV.fetch("RELEASE_CI_RUN_ID")) }
  digest = ENV.fetch("RELEASE_DIGEST")
  source = Ops::PullRequestSource.new(repository:)
  source.validate!(selection:, digest:)
  deployment = Ops::ReleaseDeployment.new(destination: "staging")
  deployment.prepare!
  Ops::PullRequestStaging.call(deployment:, source:, selection:, digest:, checkout_commit: ENV.fetch("GITHUB_SHA"))
  File.open(ENV.fetch("GITHUB_STEP_SUMMARY"), "a") do |file|
    file.puts "## PR ##{number} auf Staging"
    file.puts ""
    file.puts "- [Pull Request](https://github.com/#{repository}/pull/#{number})"
    file.puts "- Commit: `#{selection.fetch(:commit)}`"
    file.puts "- Image-Digest: `#{digest}`"
    file.puts "- [Erfolgreiche PR-CI](https://github.com/#{repository}/actions/runs/#{selection.fetch(:ci_run_id)})"
    file.puts "- [Staging öffnen](https://#{HetznerDeployConfig.app_host(destination: 'staging')}/)"
    file.puts ""
    file.puts "PR-Vorschau ohne Produktionsfreigabe. Der nächste Main-Staging-Deploy ersetzt diesen Stand."
  end
rescue KeyError, JSON::ParserError, Ops::ReleaseSupport::Error, Ops::ReleaseManifest::Error, Ops::DeployImageProof::Error, Ops::DeployLock::Error, Timeout::Error => error
  warn "PR-Staging verweigert oder Deploy fehlgeschlagen: #{error.message}"
  exit 1
end

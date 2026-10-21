require "uri"
require_relative "release_support"

module Ops
  class PullRequestSource
    def initialize(repository:, api: ReleaseSupport)
      raise ReleaseSupport::Error, "Unbekanntes Release-Repository" unless ReleaseManifest::IMAGES.key?(repository)
      @repository, @api = repository, api
    end

    def self.dispatch_number(repository:, event_name:, ref:, event:)
      unless event_name == "workflow_dispatch" && ref == "refs/heads/main" && event.dig("repository", "full_name") == repository
        raise ReleaseSupport::Error, "PR-Staging muss manuell auf main im eigenen Repository gestartet werden"
      end
      ReleaseSupport.run_id(event.fetch("inputs").fetch("pr_number"))
    end

    def resolve(pr_number:)
      number = ReleaseSupport.run_id(pr_number)
      pull = @api.github_json("repos/#{@repository}/pulls/#{number}")
      validate_pull!(pull, number)
      query = URI.encode_www_form(event: "pull_request", head_sha: pull.dig("head", "sha"), branch: pull.dig("head", "ref"), per_page: 1)
      runs = @api.github_json("repos/#{@repository}/actions/workflows/ci.yml/runs?#{query}").fetch("workflow_runs")
      run = runs.first
      validate_run!(run, pull)
      { pr_number: number, commit: pull.dig("head", "sha"), ci_run_id: run.fetch("id") }
    rescue KeyError, TypeError, NoMethodError
      raise ReleaseSupport::Error, "PR oder CI-Antwort unvollständig"
    end

    def validate!(selection:, digest:)
      unless resolve(pr_number: selection.fetch(:pr_number)) == selection
        raise ReleaseSupport::Error, "PR oder CI wurde seit dem Build verändert; Workflow erneut starten"
      end
      image = ReleaseManifest::IMAGES.fetch(@repository)
      unless digest.to_s.match?(/\Asha256:[a-f0-9]{64}\z/) && @api.registry_digest(image:, commit: selection.fetch(:commit)) == digest
        raise ReleaseSupport::Error, "PR-Image stimmt nicht mit dem gebauten Digest überein"
      end
      true
    end

    private

    def validate_pull!(pull, number)
      own = pull.dig("base", "repo")
      unless pull["number"] == number && pull["state"] == "open" && pull["merged"] == false &&
          own_repository?(own) && own_repository?(pull.dig("head", "repo"), id: own["id"]) &&
          pull.dig("base", "ref") == "main" && ReleaseManifest.sha?(pull.dig("head", "sha")) &&
          pull.dig("head", "ref").is_a?(String) && !pull.dig("head", "ref").empty?
        raise ReleaseSupport::Error, "Nur offene PRs aus dem eigenen Repository nach main sind für Staging zugelassen"
      end
    end

    def validate_run!(run, pull)
      repository_id = pull.dig("base", "repo", "id")
      valid = run.is_a?(Hash) && run["status"] == "completed" && run["conclusion"] == "success" &&
        run["event"] == "pull_request" && run["path"] == ".github/workflows/ci.yml" &&
        run["head_sha"] == pull.dig("head", "sha") && run["head_branch"] == pull.dig("head", "ref") &&
        run["id"].is_a?(Integer) && run["id"].positive? && own_repository?(run["repository"], id: repository_id) &&
        own_repository?(run["head_repository"], id: repository_id) && Array(run["pull_requests"]).any? do |candidate|
          candidate["number"] == pull["number"] && candidate.dig("head", "sha") == pull.dig("head", "sha") &&
            candidate.dig("base", "ref") == "main" && candidate.dig("base", "repo", "id") == repository_id &&
            candidate.dig("head", "repo", "id") == repository_id
        end
      raise ReleaseSupport::Error, "Der neueste CI-Lauf des aktuellen PR-Stands muss erfolgreich sein" unless valid
    end

    def own_repository?(repository, id: nil)
      repository.is_a?(Hash) && repository["full_name"] == @repository && repository["id"].is_a?(Integer) &&
        repository["id"].positive? && (id.nil? || repository["id"] == id)
    end
  end
end

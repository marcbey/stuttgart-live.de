require_relative "pull_request_source"

module Ops
  module PullRequestStaging
    def self.call(deployment:, source:, selection:, digest:, checkout_commit:)
      raise ReleaseSupport::Error, "PR-Deployments sind nur für Staging zugelassen" unless deployment.destination == "staging"
      refusal = nil
      deployment.with_lock do
        begin
          source.validate!(selection:, digest:)
        rescue ReleaseSupport::Error, KeyError, JSON::ParserError => error
          # A preflight refusal must release the fence before any host mutation.
          refusal = error
          next
        end
        deployment.deploy!(commit: selection.fetch(:commit), digest:, checkout_commit:)
        deployment.smoke_peer!
        deployment.notify_sentry!(commit: selection.fetch(:commit))
      end
      raise refusal if refusal
      true
    end
  end
end

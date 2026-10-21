require_relative "pull_request_source"

begin
  repository = Ops::ReleaseSupport.repository
  number = Ops::PullRequestSource.dispatch_number(repository:, event_name: ENV.fetch("GITHUB_EVENT_NAME"), ref: ENV.fetch("GITHUB_REF"),
    event: JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))))
  selection = Ops::PullRequestSource.new(repository:).resolve(pr_number: number)
  File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |file|
    selection.each { |key, value| file.puts "#{key}=#{value}" }
  end
rescue KeyError, JSON::ParserError, Ops::ReleaseSupport::Error => error
  warn "PR-Staging-Quelle verweigert: #{error.message}"
  exit 1
end

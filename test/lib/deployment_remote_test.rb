require "test_helper"
require "support/deploy_config_helper"
require_relative "../../script/ops/deployment_remote"

class DeploymentRemoteTest < ActiveSupport::TestCase
  include DeployConfigHelper

  IMAGE = "ghcr.io/marcbey/stuttgart-live-de"
  COMMIT = "a" * 40
  TAG = "#{IMAGE}:#{COMMIT}"
  DIGEST = "sha256:#{'d' * 64}"

  test "cached images retain the digest recorded when their container was deployed" do
    remote = fixture_remote(digests: [ "sha256:#{'b' * 64}", DIGEST ])
    identity = remote.running(project: "stuttgart_live_de", destination: "staging")
    assert_equal({ "container" => "123456abcdef", "commit" => COMMIT, "image" => IMAGE, "digest" => DIGEST }, identity)
  end

  test "a recorded digest absent from the local image cannot identify the container" do
    remote = fixture_remote(digests: [ "sha256:#{'b' * 64}" ])
    assert_raises(Ops::DeployImageProof::Error) { remote.running(project: "stuttgart_live_de", destination: "staging") }
  end

  test "recorded digests cannot hide a different running image" do
    remote = fixture_remote(digests: [ "sha256:#{'b' * 64}", DIGEST ], container_id: "sha256:#{'e' * 64}")
    assert_raises(Ops::DeployImageProof::Error) { remote.running(project: "stuttgart_live_de", destination: "staging") }
  end

  test "legacy containers need exactly one unambiguous digest" do
    remote = fixture_remote(digests: [ "sha256:#{'b' * 64}" ], recorded_digest: "")
    assert_equal "sha256:#{'b' * 64}", remote.running(project: "stuttgart_live_de", destination: "hetzner").fetch("digest")
    remote = fixture_remote(digests: [ "sha256:#{'b' * 64}", DIGEST ], recorded_digest: "")
    assert_raises(Ops::ReleaseSupport::Error) { remote.running(project: "stuttgart_live_de", destination: "staging") }
  end

  test "Kamal records the proven release digest on every role in both destinations" do
    %w[staging hetzner].each do |destination|
      raw = render_deploy_config(destination:, env: { "RELEASE_DIGEST" => DIGEST })
      config = Kamal::Configuration.new(raw.symbolize_keys, destination:)
      config.roles.each { |role| assert_equal DIGEST, role.labels.transform_keys(&:to_s).fetch("live.release_digest") }
    end
  end

  private

  def fixture_remote(digests:, container_id: "sha256:#{'c' * 64}", recorded_digest: DIGEST)
    remote = Ops::DeploymentRemote.new(key_path: "/unused")
    image = { "id" => "sha256:#{'c' * 64}", "digests" => digests.map { |digest| "#{IMAGE}@#{digest}" } }
    remote.define_singleton_method(:capture) do |command, **|
      case command
      when /\Adocker ps / then "123456abcdef\n"
      when /\Adocker inspect / then JSON.generate("image" => TAG, "id" => container_id, "digest" => recorded_digest)
      when /\Adocker image inspect / then JSON.generate(image)
      else raise "Unexpected remote command: #{command}"
      end
    end
    remote
  end
end

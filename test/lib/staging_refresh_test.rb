require "test_helper"
require "json"
require "tmpdir"
require_relative "../../script/ops/staging_refresh"

class StagingRefreshTest < ActiveSupport::TestCase
  class Backend
    attr_reader :calls
    attr_accessor :fail_at

    def initialize
      @calls = []
    end

    def with_lock
      @calls << :lock
      yield
    ensure
      @calls << :unlock
    end

    def run(phase, _script)
      @calls << phase
      raise "injected failure" if phase == fail_at
    end
  end

  def manifest
    {
      "schema_version" => 1, "snapshot_id" => "20261017-test01", "host" => "46.225.224.194",
      "source_volume" => "stuttgart_live_de_storage", "target_volume" => "stuttgart_live_de_staging_storage",
      "apps" => {
        "stuttgart_live_de" => { "source_database" => "stuttgart_live_de_production", "target_database" => "stuttgart_live_de_staging", "image" => "ghcr.io/marcbey/stuttgart-live-de@sha256:#{'a' * 64}", "schema_sha256" => "b" * 64, "schema_version" => "20261001000000" },
        "russ_live_de" => { "source_database" => "russ_live_de_production", "target_database" => "russ_live_de_staging", "image" => "ghcr.io/marcbey/russ-live-de@sha256:#{'c' * 64}", "schema_sha256" => "d" * 64, "schema_version" => "20260929103000" }
      }
    }
  end

  test "dry run validates and plans without even opening a remote connection" do
    backend = Backend.new
    result = Ops::StagingRefresh.new(manifest:, backend:).call
    assert_empty backend.calls
    assert_includes result, "Staging bleibt bis zur vollständigen Prüfung gesperrt"
  end

  test "unknown or production targets are rejected before lock and every write" do
    changes = [
      ->(m) { m["target_volume"] = "stuttgart_live_de_storage" },
      ->(m) { m["apps"]["stuttgart_live_de"]["target_database"] = "stuttgart_live_de_production" },
      ->(m) { m["apps"]["russ_live_de"]["target_database"] = "stuttgart_live_de_staging" },
      ->(m) { m["apps"]["russ_live_de"]["source_database"] = "russ_live_de_staging" },
      ->(m) { m["apps"]["other"] = m["apps"]["russ_live_de"] },
      ->(m) { m["apps"]["russ_live_de"]["image"] = "ghcr.io/marcbey/russ-live-de:latest" },
      ->(m) { m["snapshot_id"] = "../../production" }
    ]
    changes.each do |change|
      data = manifest
      change.call(data)
      backend = Backend.new
      assert_raises(Ops::StagingRefresh::Error) { Ops::StagingRefresh.new(manifest: data, backend:).call(execute: true) }
      assert_empty backend.calls
    end
  end

  test "readiness is last and refresh never starts old web or workers" do
    backend = Backend.new
    Ops::StagingRefresh.new(manifest:, backend:).call(execute: true)
    assert_equal [ :lock, :preflight, :stop, :clear_readiness, :copy_media_first, :snapshot, :restore, :copy_media_second,
      :sanitize, :reset_operational, :migrate, :grants, :verify, :ready, :unlock ], backend.calls
  end

  test "restore sanitizer and missing-media failures leave readiness absent and stage stopped" do
    %i[restore sanitize verify].each do |phase|
      backend = Backend.new
      backend.fail_at = phase
      assert_raises(RuntimeError) { Ops::StagingRefresh.new(manifest:, backend:).call(execute: true) }
      assert_includes backend.calls, :stop
      assert_includes backend.calls, :clear_readiness
      assert_not_includes backend.calls, :ready
      assert_equal :unlock, backend.calls.last
    end
  end

  test "server scripts parse as bash and use exact destinations without any restart" do
    refresh = Ops::StagingRefresh.new(manifest:)
    scripts = Ops::StagingRefresh::PHASES.to_h { |phase| [ phase, refresh.script(phase) ] }
    scripts.each_value do |script|
      _, error, status = Open3.capture3("bash", "-n", stdin_data: script)
      assert status.success?, error
    end
    assert_includes scripts.fetch(:restore), "--role stuttgart_live_de_staging --dbname stuttgart_live_de_staging"
    assert_includes scripts.fetch(:reset_operational), "dropdb --force --if-exists russ_live_de_staging_queue"
    assert_includes scripts.fetch(:sanitize), "--interactive"
    assert_includes scripts.fetch(:sanitize), " < /etc/live-staging/staging-admin-password"
    assert_includes scripts.fetch(:preflight), "DeploymentEnvironment.validate_runtime"
    assert_includes scripts.fetch(:preflight), "--network none --env-file /etc/live-staging/russ_live_de.env"
    assert_no_match(/docker (start|restart)|kamal .*boot/, scripts.values.join)
    assert_includes scripts.fetch(:ready), "mv -T"
  end

  test "real remote protocol keeps commands in one lease and hides failed command output" do
    Dir.mktmpdir do |root|
      ssh = File.join(root, "ssh")
      key = File.join(root, "key")
      lock = File.join(root, "lock")
      output = File.join(root, "output")
      File.write(key, "fixture")
      File.write(ssh, <<~PYTHON, mode: "w", perm: 0o700)
        #!/usr/bin/env python3
        import fcntl, shlex, subprocess, sys
        assert 'admin@test.invalid' in sys.argv
        args = shlex.split(sys.argv[-1])
        index = args.index('/var/lock/live-deploy/global.lock')
        args[-1] = args[-1].replace('/var/lock/live-deploy/active-operation', #{"#{lock}.fence".inspect})
        with open(#{lock.inspect}, 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            sys.exit(subprocess.call(args[index + 1:]))
      PYTHON
      previous = ENV["PATH"]
      ENV["PATH"] = "#{root}:#{previous}"
      remote = Ops::StagingRefresh::Remote.new(host: "test.invalid", key_path: key)
      _out, err = capture_io do
        assert_raises(Ops::StagingRefresh::Error) do
          remote.with_lock do
            remote.run(:one, "printf 'verified' > #{Shellwords.escape(output)}")
            remote.run(:two, "printf 'private-token'; exit 12")
          end
        end
      end
      assert_equal "verified", File.read(output)
      assert_not_includes err, "private-token"
      assert File.directory?("#{lock}.fence")
      assert_raises(Ops::StagingRefresh::Error) { remote.with_lock { flunk "Failed refresh fence ignored" } }
      File.unlink("#{lock}.fence/owner")
      Dir.rmdir("#{lock}.fence")
      capture_io { remote.with_lock { remote.run(:released, "true") } }
      refute File.exist?("#{lock}.fence")
    ensure
      ENV["PATH"] = previous
    end
  end
end

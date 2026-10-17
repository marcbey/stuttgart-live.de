require "json"
require "shellwords"
require "open3"
require "base64"
require "timeout"
require "securerandom"
require_relative "host_operation_fence"

module Ops
  class StagingRefresh
    Error = Class.new(StandardError)
    PROJECTS = %w[stuttgart_live_de russ_live_de].freeze
    SOURCE_VOLUME = "stuttgart_live_de_storage".freeze
    TARGET_VOLUME = "stuttgart_live_de_staging_storage".freeze
    SECRET_ROOT = "/etc/live-staging".freeze
    SNAPSHOT_ROOT = "/var/lib/live-staging-refresh".freeze
    DATA_ROOT = "/var/lib/docker/volumes/#{TARGET_VOLUME}/_data".freeze
    PHASES = %i[preflight stop clear_readiness copy_media_first snapshot restore copy_media_second sanitize reset_operational migrate grants verify ready].freeze

    def initialize(manifest:, backend: nil)
      @manifest = manifest
      @backend = backend
    end

    def call(execute: false)
      validate!
      return "Refresh #{snapshot_id}: ausschließlich acht Staging-Datenbanken und #{TARGET_VOLUME}. Staging bleibt bis zur vollständigen Prüfung gesperrt. Keine Mutation im Dry-Run." unless execute

      backend = @backend || Remote.new(host: @manifest.fetch("host"))
      backend.with_lock do
        PHASES.each { |phase| backend.run(phase, script(phase)) }
      end
      "Refresh geprüft; Readiness geschrieben. Staging anschließend über den regulären Deployment-Ablauf starten."
    end

    def validate!
      expected = %w[apps host schema_version snapshot_id source_volume target_volume]
      raise Error, "Unbekannte Manifestfelder" unless @manifest.is_a?(Hash) && @manifest.keys.sort == expected.sort
      unless @manifest["schema_version"] == 1 && @manifest["host"] == "46.225.224.194" &&
          @manifest["source_volume"] == SOURCE_VOLUME && @manifest["target_volume"] == TARGET_VOLUME &&
          snapshot_id.to_s.match?(/\A[a-z0-9][a-z0-9-]{7,63}\z/)
        raise Error, "Ungültige oder produktive Refresh-Ziele"
      end
      apps = @manifest["apps"]
      raise Error, "Exakt beide Apps erforderlich" unless apps.is_a?(Hash) && apps.keys.sort == PROJECTS.sort
      PROJECTS.each do |project|
        app = apps[project]
        fields = %w[image schema_sha256 schema_version source_database target_database]
        raise Error, "Unbekannte App-Felder" unless app.is_a?(Hash) && app.keys.sort == fields.sort
        unless app["source_database"] == "#{project}_production" && app["target_database"] == "#{project}_staging" &&
            app["source_database"] != app["target_database"] && app["schema_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/) &&
            app["schema_version"].to_s.match?(/\A[0-9]{14}\z/) &&
            app["image"].to_s.match?(/\Aghcr\.io\/marcbey\/#{project.tr('_', '-')}@sha256:[a-f0-9]{64}\z/)
          raise Error, "Ungültige App-Zuordnung oder nicht fixiertes Image"
        end
      end
      true
    end

    def script(phase)
      validate!
      body = case phase
      when :preflight then preflight
      when :stop then stop
      when :clear_readiness then "rm -f #{q("#{DATA_ROOT}/.staging-ready.json")} #{q("#{DATA_ROOT}/.staging-ready.json.tmp")}"
      when :copy_media_first, :copy_media_second then copy_media
      when :snapshot then snapshot
      when :restore then restore
      when :sanitize then app_commands("runner script/staging/sanitize.rb", admin: true)
      when :reset_operational then reset_operational
      when :migrate then app_commands("db:prepare")
      when :grants then grants
      when :verify then app_commands("runner script/staging/verify.rb")
      when :ready then ready
      else raise Error, "Unbekannte Refresh-Phase"
      end
      "set -euo pipefail\numask 077\n#{body}\n"
    end

    private

    def snapshot_id
      @manifest["snapshot_id"]
    end

    def directory
      "#{SNAPSHOT_ROOT}/#{snapshot_id}"
    end

    def q(value)
      Shellwords.escape(value.to_s)
    end

    def postgres(command)
      "runuser -u postgres -- #{command}"
    end

    def sql(database, statement)
      postgres("psql --no-psqlrc --set ON_ERROR_STOP=1 --dbname #{q(database)} --tuples-only --no-align --command #{q(statement)}")
    end

    def preflight
      checks = [ "command -v rsync >/dev/null", "command -v flock >/dev/null", "test ! -e #{q(directory)}" ]
      [ SOURCE_VOLUME, TARGET_VOLUME ].each do |volume|
        checks << "test \"$(docker volume inspect --format '{{.Driver}} {{.Mountpoint}} {{json .Options}}' #{q(volume)})\" = #{q("local /var/lib/docker/volumes/#{volume}/_data null")}"
      end
      checks << "test \"$(docker volume inspect --format '{{index .Labels \"live.environment\"}}' #{TARGET_VOLUME})\" = staging"
      PROJECTS.each do |project|
        file = "#{SECRET_ROOT}/#{project}.env"
        checks << private_file(file)
        app = @manifest.fetch("apps").fetch(project)
        validation = "require './app/lib/deployment_environment'; abort unless ENV['RAILS_ENV'] == 'production' && ENV['APP_ENVIRONMENT'] == 'staging'; DeploymentEnvironment.validate_runtime!(project: '#{project}'); DeploymentEnvironment.validate_credentials!(root: '/rails', environment: 'staging')"
        checks << "docker run --rm --network none --env-file #{file} --entrypoint ruby #{q(app.fetch('image'))} -e #{q(validation)}"
        schema = project == "stuttgart_live_de" ? "/rails/db/schema.rb" : "/rails/db/russ_schema.rb"
        checks << "test \"$(docker run --rm --network none --entrypoint sha256sum #{q(app.fetch('image'))} #{schema} | cut -d' ' -f1)\" = #{q(app.fetch('schema_sha256'))}"
        checks << "test \"$(#{sql(app.fetch('source_database'), 'SELECT MAX(version) FROM schema_migrations')})\" = #{q(app.fetch('schema_version'))}"
        checks << "test \"$(docker run --rm --network none --entrypoint sed #{q(app.fetch('image'))} -n '/ActiveRecord::Schema.*define(version:/p' #{schema} | tr -cd '0-9' | cut -c3-)\" = #{q(app.fetch('schema_version'))}"
      end
      checks << private_file("#{SECRET_ROOT}/staging-admin-password")
      checks << "test $(wc -c < #{SECRET_ROOT}/staging-admin-password) -ge 32"
      # Stop before writing anything if the host lacks the agreed rolling reserve.
      checks << "test $(awk '/MemAvailable:/ {print $2}' /proc/meminfo) -ge 1048576"
      checks << "test $(df --output=avail -k /var/lib/docker | tail -1) -ge 10485760"
      checks.join("\n")
    end

    def private_file(path)
      "test ! -L #{q(path)}; test \"$(stat -c '%u:%a' #{q(path)})\" = '0:600'"
    end

    def stop
      commands = [ "rm -f #{q("#{DATA_ROOT}/.staging-ready.json")}" ]
      PROJECTS.each do |project|
        commands << <<~BASH
          mapfile -t containers < <(docker ps -q --filter label=service=#{project} --filter label=destination=staging)
          if ((${#containers[@]})); then docker stop --time 45 "${containers[@]}"; fi
          test -z "$(docker ps -q --filter label=service=#{project} --filter label=destination=staging)"
        BASH
      end
      commands.join("\n")
    end

    def copy_media
      "rsync --archive --delete --exclude=.staging-ready.json --exclude=.staging-ready.json.tmp /var/lib/docker/volumes/#{SOURCE_VOLUME}/_data/ #{DATA_ROOT}/\nchown -R 1000:1000 #{DATA_ROOT}"
    end

    def snapshot
      commands = [ "install -d -m 0700 #{q(directory)}" ]
      PROJECTS.each do |project|
        commands << "#{postgres("pg_dump --format=custom --no-owner --no-acl --dbname #{project}_production")} > #{q("#{directory}/#{project}.dump") }"
        commands << "test -s #{q("#{directory}/#{project}.dump")}"
      end
      commands.join("\n")
    end

    def restore
      PROJECTS.map do |project|
        # The pipe is opened by root; postgres never needs access to the private directory.
        "#{sql('postgres', "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '#{project}_staging' AND pid <> pg_backend_pid()") }\n" \
          "#{postgres("pg_restore --exit-on-error --clean --if-exists --no-owner --no-acl --role #{project}_staging --dbname #{project}_staging")} < #{q("#{directory}/#{project}.dump")}"
      end.join("\n")
    end

    def app_commands(command, admin: false)
      PROJECTS.map do |project|
        image = @manifest.fetch("apps").fetch(project).fetch("image")
        secret = admin && project == "stuttgart_live_de"
        input = secret ? " < #{SECRET_ROOT}/staging-admin-password" : ""
        interactive = secret ? " --interactive" : ""
        # Environment files are a separate private operation artifact, never Kamal's production files.
        prefix = admin && project == "russ_live_de" ? "#{grants}\n" : ""
        "#{prefix}docker run --rm#{interactive} --network kamal --env-file #{SECRET_ROOT}/#{project}.env --mount type=volume,src=#{TARGET_VOLUME},dst=/rails/storage --entrypoint ./bin/rails #{q(image)} #{command}#{input}"
      end.join("\n")
    end

    def reset_operational
      PROJECTS.flat_map do |project|
        %w[cache queue cable].map do |suffix|
          database = "#{project}_staging_#{suffix}"
          "#{postgres("dropdb --force --if-exists #{database}")}\n#{postgres("createdb --owner #{project}_staging #{database}")}"
        end
      end.join("\n")
    end

    def grants
      statements = PROJECTS.flat_map do |project|
        [ "", "_cache", "_queue", "_cable" ].map do |suffix|
          database = "#{project}_staging#{suffix}"
          sql(database, "REVOKE ALL ON DATABASE #{database} FROM PUBLIC; REVOKE ALL ON SCHEMA public FROM PUBLIC; GRANT ALL ON SCHEMA public TO #{project}_staging;")
        end
      end
      statements << sql("stuttgart_live_de_staging", <<~SQL.split.join(" "))
        GRANT CONNECT ON DATABASE stuttgart_live_de_staging TO russ_live_de_staging_reader;
        GRANT USAGE ON SCHEMA public TO russ_live_de_staging_reader;
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO russ_live_de_staging_reader;
        ALTER DEFAULT PRIVILEGES FOR ROLE stuttgart_live_de_staging IN SCHEMA public GRANT SELECT ON TABLES TO russ_live_de_staging_reader;
      SQL
      statements.join("\n")
    end

    def ready
      marker = { schema_version: 1, environment: "staging", volume: TARGET_VOLUME, refresh_id: snapshot_id,
        databases: PROJECTS.to_h { |project| [ project, "#{project}_staging" ] } }
      <<~BASH
        rm -f #{q("#{directory}/stuttgart_live_de.dump")} #{q("#{directory}/russ_live_de.dump")}
        printf '%s\n' #{q(JSON.generate(marker))} > #{DATA_ROOT}/.staging-ready.json.tmp
        chown 1000:1000 #{DATA_ROOT}/.staging-ready.json.tmp
        chmod 0640 #{DATA_ROOT}/.staging-ready.json.tmp
        mv -T #{DATA_ROOT}/.staging-ready.json.tmp #{DATA_ROOT}/.staging-ready.json
      BASH
    end

    # The persistent fence also blocks deployments if SSH/flock dies before a child.
    class Remote
      PROGRAM = <<~'BASH'.freeze
        set -uo pipefail
        printf '__REFRESH_LOCKED\n'
        while IFS= read -r payload; do
          if [ "$payload" = "RELEASE OPERATION_OWNER" ]; then
            OPERATION_RELEASE
            printf '__REFRESH_RELEASED\n'
            exit 0
          fi
          if printf '%s' "$payload" | base64 --decode | bash -euo pipefail >/dev/null 2>&1; then
            printf '__REFRESH_STATUS_0\n'
          else
            printf '__REFRESH_STATUS_1\n'
            exit 1
          fi
        done
        exit 75
      BASH

      def initialize(host:, key_path: File.expand_path("~/.ssh/stgt-live-hetzner-admin"))
        @host, @key_path = host, key_path
      end

      def with_lock
        raise Error, "SSH-Key fehlt" unless File.file?(@key_path)
        operation = SecureRandom.hex(16)
        program = "set -e\n#{HostOperationFence.acquire_script(owner: operation)}\n" +
          PROGRAM.sub("OPERATION_OWNER", operation).sub("OPERATION_RELEASE", HostOperationFence.release_script(owner: operation))
        remote = "sudo -n flock -w 900 -E 75 /var/lock/live-deploy/global.lock bash -c #{Shellwords.escape(program)}"
        args = [ "ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
          "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2", "-i", @key_path, "admin@#{@host}", remote ]
        Open3.popen3(*args) do |input, output, error, waiter|
          @input, @output = input, output
          drain = Thread.new { error.each_line { |_line| } }
          begin
            raise Error, "Refresh-Sperre nicht verfügbar; unabgeschlossene Host-Operation administrativ prüfen" unless Timeout.timeout(915) { output.gets } == "__REFRESH_LOCKED\n"
            yield
            input.puts("RELEASE #{operation}")
            input.flush
            raise Error, "Refresh-Sperre nicht sauber freigegeben" unless Timeout.timeout(5) { output.gets } == "__REFRESH_RELEASED\n" && waiter.value.success?
          ensure
            input.close unless input.closed?
            # The persistent fence survives transport or supervisor loss.
            unless waiter.join(5)
              Process.kill("TERM", waiter.pid) rescue nil
              waiter.join
            end
            drain.join
            @input = @output = nil
          end
        end
      rescue Timeout::Error, IOError, Errno::EPIPE
        raise Error, "Refresh-Verbindung unterbrochen; Staging bleibt gesperrt"
      end

      def run(phase, script)
        puts "Staging-Refresh: #{phase}"
        @input.puts(Base64.strict_encode64(script))
        @input.flush
        result = Timeout.timeout(3600) { @output.gets }
        raise Error, "Refresh-Phase #{phase} fehlgeschlagen; Staging bleibt gesperrt" unless result == "__REFRESH_STATUS_0\n"
      end
    end
  end
end

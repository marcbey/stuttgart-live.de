require "test_helper"
require "open3"

class StagingInventoryTest < ActiveSupport::TestCase
  test "Ansible databases and roles match both validated app profiles" do
    path = Rails.root.join("infra/ansible/roles/staging_postgres/defaults/main.yml")
    assert_path_exists path
    config = YAML.safe_load_file(path)
    stuttgart = DeploymentEnvironment.staging_profile(project: "stuttgart_live_de")
    russ = DeploymentEnvironment.staging_profile(project: "russ_live_de")
    expected_databases = stuttgart.values_at("DB_NAME", "CACHE_DB_NAME", "QUEUE_DB_NAME", "CABLE_DB_NAME") +
      russ.values_at("RUSS_DB_NAME", "CACHE_DB_NAME", "QUEUE_DB_NAME", "CABLE_DB_NAME")
    assert_equal expected_databases.sort, config.fetch("staging_postgres_databases").map { |db| db.fetch("name") }.sort
    assert_equal stuttgart.values_at("DB_USER") + russ.values_at("DB_USER", "OPERATIONAL_DB_USER"), config.fetch("staging_postgres_roles").map { |role| role.fetch("name") }
    assert_equal "172.18.0.0/16", config.fetch("staging_postgres_docker_subnet")
  end

  test "staging provisioner passes only a protected vars-file path to Ansible" do
    with_provisioner do |root, env, vars, log|
      File.write(root.join(".env"), "exit 23\n")
      output, status = Open3.capture2e(env, "bash", root.join("script/ansible_app_host_staging").to_s, "--vars-file", vars.to_s, "--check")
      assert status.success?, output
      arguments = File.readlines(log, chomp: true)
      assert_includes arguments, "@#{vars}"
      refute arguments.any? { |argument| argument.include?("synthetic-password") }
      assert arguments.any? { |argument| argument.end_with?("playbooks/staging.yml") }
      FileUtils.chmod(0o644, vars)
      output, status = Open3.capture2e(env, "bash", root.join("script/ansible_app_host_staging").to_s, "--vars-file", vars.to_s)
      refute status.success?
      assert_includes output, "Dateirechte"
    end
  end

  test "staging provisioner runs apply without optional flags on the system Bash" do
    with_provisioner do |root, env, vars, log|
      output, status = Open3.capture2e(env, "/bin/bash", root.join("script/ansible_app_host_staging").to_s, "--vars-file", vars.to_s)
      assert status.success?, output
      arguments = File.readlines(log, chomp: true)
      assert_includes arguments, "@#{vars}"
      refute_includes arguments, "--check"
    end
  end

  private

  def with_provisioner
    source = Rails.root.join("script/ansible_app_host_staging")
    assert_path_exists source
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      FileUtils.mkdir_p(root.join("script"))
      FileUtils.cp(source, root.join("script/ansible_app_host_staging"))
      FileUtils.cp_r(Rails.root.join("infra"), root.join("infra"))
      bin = root.join("fake-bin")
      FileUtils.mkdir_p(bin)
      File.write(bin.join("ansible-playbook"), "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$ANSIBLE_TEST_LOG\"\n")
      FileUtils.chmod(0o700, bin.join("ansible-playbook"))
      vars = root.join("staging-secrets.yml")
      names = %w[staging_stuttgart_db_password staging_russ_reader_password staging_russ_operational_password]
      File.write(vars, names.each_with_index.to_h { |name, index| [ name, "synthetic-password-#{index}-#{'a' * 32}" ] }.to_yaml)
      FileUtils.chmod(0o600, vars)
      key = root.join("synthetic-key")
      File.write(key, "fixture")
      log = root.join("ansible-args.log")
      yield root, { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "SSH_KEY" => key.to_s, "ANSIBLE_TEST_LOG" => log.to_s }, vars, log
    end
  end
end

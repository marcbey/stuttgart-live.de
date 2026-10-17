abort "Nur Staging erlaubt" unless Rails.configuration.x.deployment_environment == "staging"
DeploymentEnvironment.validate_runtime!(project: "stuttgart_live_de")
begin
  connection = ApplicationRecord.connection
  admins = connection.select_all("SELECT id, email_address FROM users WHERE role = 'admin'")
  raise Staging::DataSanitizer::Error, "Admin-Prüfung fehlgeschlagen" unless admins.one? && admins.first["email_address"] == "staging-admin@example.invalid"
  Staging::DataSanitizer.new(connection:).verify!(admin_id: admins.first.fetch("id"))
  Staging::MediaVerifier.call(connection:)
rescue StandardError
  abort "Staging-Nutzer-/Token-/Medienprüfung fehlgeschlagen; keine Datensätze oder Secrets ausgegeben."
end
load Rails.root.join("script/ops/check_staging_acl.rb")

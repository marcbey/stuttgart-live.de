# Offline Rails runner. The stage services remain stopped throughout the refresh.
abort "Nur Staging erlaubt" unless Rails.configuration.x.deployment_environment == "staging"
DeploymentEnvironment.validate_runtime!(project: "stuttgart_live_de")
connection = ApplicationRecord.connection
sanitizer = Staging::DataSanitizer.new(connection:)
password = STDIN.read(1024).chomp
abort "Ungültiges Staging-Admin-Passwort" unless password.length.between?(32, 72)
begin
  connection.transaction do
    counts = sanitizer.call
    admin_id = sanitizer.create_admin!(password:)
    sanitizer.verify!(admin_id:)
    puts "Bereinigte Tabellen: #{counts.size}; genau ein eigener Staging-Admin angelegt."
  end
rescue StandardError
  abort "Staging-Bereinigung fehlgeschlagen; keine Datensätze oder Secrets ausgegeben."
end

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

ImportSource.ensure_supported_sources!

{
  "easyticket" => 0,
  "reservix" => 10,
  "eventim" => 20
}.each do |source_type, priority_rank|
  ProviderPriority.find_or_initialize_by(source_type: source_type).tap do |priority|
    priority.priority_rank = priority_rank
    priority.active = true
    priority.save!
  end
end

%w[Rock Pop Hip-Hop Metal Jazz Klassik Indie Electro].each do |name|
  Genre.find_or_create_by!(name: name) do |genre|
    genre.slug = name.parameterize
  end
end

default_admin_email = ENV.fetch("DEFAULT_ADMIN_EMAIL", "admin@stuttgart-live.de")
default_admin_password = ENV.fetch("DEFAULT_ADMIN_PASSWORD", "PleaseChangeMe123!")

admin = User.find_or_initialize_by(email_address: default_admin_email)
admin.name = admin.name.presence || "Admin"
admin.role = "admin"
if admin.new_record? || default_admin_password != "PleaseChangeMe123!"
  admin.password = default_admin_password
  admin.password_confirmation = default_admin_password
end
admin.save!

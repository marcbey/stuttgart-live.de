module ApplicationHelper
  def compiled_asset_exists?(logical_path)
    manifest_assets =
      if Rails.application.respond_to?(:assets_manifest)
        Rails.application.assets_manifest&.assets
      end
    return true if manifest_assets&.key?(logical_path)

    builds_path = Rails.root.join("app/assets/builds", logical_path)
    return true if File.exist?(builds_path)

    propshaft_path = Rails.root.join("app/assets", logical_path)
    File.exist?(propshaft_path)
  rescue StandardError
    false
  end
end

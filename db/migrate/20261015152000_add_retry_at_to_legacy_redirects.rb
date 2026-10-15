class AddRetryAtToLegacyRedirects < ActiveRecord::Migration[8.1]
  def change
    add_column :legacy_redirects, :retry_at, :datetime
  end
end

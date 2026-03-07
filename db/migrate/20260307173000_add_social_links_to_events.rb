class AddSocialLinksToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :homepage_url, :string
    add_column :events, :instagram_url, :string
    add_column :events, :facebook_url, :string
  end
end

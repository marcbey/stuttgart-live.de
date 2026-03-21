class MakePresenterExternalUrlOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :presenters, :external_url, true
  end
end

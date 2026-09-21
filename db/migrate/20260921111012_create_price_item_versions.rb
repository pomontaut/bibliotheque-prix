class CreatePriceItemVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :price_item_versions do |t|
      t.references :price_item, null: false, foreign_key: true
      t.decimal :reference_price, precision: 12, scale: 2, null: false
      t.datetime :changed_at, null: false

      t.timestamps
    end
  end
end

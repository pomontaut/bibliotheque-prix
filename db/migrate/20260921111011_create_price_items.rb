class CreatePriceItems < ActiveRecord::Migration[8.1]
  def change
    create_table :price_items do |t|
      t.string :name, null: false
      t.string :category
      t.string :unit
      t.decimal :reference_price, precision: 12, scale: 2, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :price_items, :name
    add_index :price_items, :category
  end
end

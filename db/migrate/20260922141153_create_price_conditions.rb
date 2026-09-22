class CreatePriceConditions < ActiveRecord::Migration[8.1]
  def change
    create_table :price_conditions do |t|
      t.references :supplier, null: false, foreign_key: true
      t.references :price_item, null: false, foreign_key: true
      t.decimal :negotiated_price, precision: 12, scale: 2, null: false
      t.string :unit
      t.date :valid_from, null: false
      t.date :valid_until
      t.text :notes

      t.timestamps
    end

    add_index :price_conditions, %i[supplier_id price_item_id valid_from], unique: true,
              name: "index_price_conditions_on_supplier_item_valid_from"
  end
end

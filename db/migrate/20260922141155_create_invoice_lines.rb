class CreateInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_lines do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :price_item, foreign_key: true
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 3
      t.decimal :unit_price, precision: 12, scale: 2
      t.decimal :total, precision: 12, scale: 2
      t.decimal :ratio, precision: 8, scale: 4
      t.boolean :matched_automatically, null: false, default: false

      t.timestamps
    end
  end
end

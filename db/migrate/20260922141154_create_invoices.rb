class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :supplier, null: false, foreign_key: true
      t.string :invoice_number
      t.date :invoice_date
      t.string :status, null: false, default: "pending"
      t.text :raw_text

      t.timestamps
    end
  end
end

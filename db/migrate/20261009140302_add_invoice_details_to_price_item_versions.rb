class AddInvoiceDetailsToPriceItemVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :price_item_versions, :invoice_date, :date
    add_column :price_item_versions, :quantity, :decimal, precision: 12, scale: 3
    add_column :price_item_versions, :total, :decimal, precision: 12, scale: 2
  end
end

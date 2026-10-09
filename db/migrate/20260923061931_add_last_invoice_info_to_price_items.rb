class AddLastInvoiceInfoToPriceItems < ActiveRecord::Migration[8.1]
  def change
    add_column :price_items, :last_invoice_number, :string
    add_column :price_items, :last_invoice_date, :date
  end
end

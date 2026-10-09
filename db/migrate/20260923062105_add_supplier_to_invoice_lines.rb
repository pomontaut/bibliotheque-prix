class AddSupplierToInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoice_lines, :supplier, null: true, foreign_key: true
  end
end

class AddUnitToInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_lines, :unit, :string
  end
end

class AddArticleNumberToInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_lines, :article_number, :string
  end
end

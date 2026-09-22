class AddArticleFieldsToPriceItems < ActiveRecord::Migration[8.1]
  def change
    add_column :price_items, :article_number, :string
    add_column :price_items, :last_order_quantity, :decimal, precision: 12, scale: 3
    add_index :price_items, :article_number
  end
end

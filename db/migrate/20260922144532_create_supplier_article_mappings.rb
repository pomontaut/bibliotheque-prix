class CreateSupplierArticleMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :supplier_article_mappings do |t|
      t.references :supplier, null: false, foreign_key: true
      t.string :article_number, null: false
      t.references :price_item, null: false, foreign_key: true

      t.timestamps
    end

    add_index :supplier_article_mappings, %i[supplier_id article_number], unique: true
  end
end

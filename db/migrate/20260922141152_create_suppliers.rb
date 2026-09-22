class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.string :name
      t.text :notes

      t.timestamps
    end
    add_index :suppliers, :name, unique: true
  end
end

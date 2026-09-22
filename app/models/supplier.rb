class Supplier < ApplicationRecord
  has_many :price_conditions, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :supplier_article_mappings, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  def active_condition_for(price_item, on: Date.current)
    price_conditions
      .where(price_item: price_item)
      .where("valid_from <= ?", on)
      .where("valid_until IS NULL OR valid_until >= ?", on)
      .order(valid_from: :desc)
      .first
  end
end

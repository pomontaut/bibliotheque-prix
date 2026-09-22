# Learned rapprochement: once a human confirms that a supplier's article
# number corresponds to a given PriceItem, future invoice lines from that
# supplier with the same article_number are matched with full confidence,
# skipping the fuzzy PriceItemMatcher entirely.
class SupplierArticleMapping < ApplicationRecord
  belongs_to :supplier
  belongs_to :price_item

  validates :article_number, presence: true, uniqueness: { scope: :supplier_id }

  def self.remember(supplier:, article_number:, price_item:)
    return if article_number.blank?

    mapping = find_or_initialize_by(supplier: supplier, article_number: article_number)
    mapping.price_item = price_item
    mapping.save!
  end
end

class PriceItem < ApplicationRecord
  has_many :price_item_versions, -> { order(changed_at: :desc) }, dependent: :destroy
  has_many :price_conditions, dependent: :destroy
  has_many :invoice_lines, dependent: :nullify
  # Deleting an article must also forget its learned article-number mapping
  # — otherwise a future invoice with that same article number would find
  # the mapping and silently recreate the very article a human deleted.
  has_many :supplier_article_mappings, dependent: :destroy

  validates :name, presence: true
  validates :reference_price, numericality: { greater_than_or_equal_to: 0 }

  before_update :record_price_change, if: :will_save_change_to_reference_price?
  after_create :record_initial_price

  scope :search, ->(query) {
    return all if query.blank?

    like = "%#{sanitize_sql_like(query)}%"
    where("name LIKE ? OR category LIKE ? OR notes LIKE ?", like, like, like)
  }
  scope :in_category, ->(category) { category.present? ? where(category: category) : all }

  def self.categories
    distinct.pluck(:category).compact.reject(&:blank?).sort
  end

  private

  def record_price_change
    # The price being archived here is the OLD one (reference_price_was) —
    # so the invoice/quantity/total that go with it must be the OLD values
    # too (the "_was" attributes), i.e. whatever was in effect while that
    # price was the current one, not the values this very update is setting.
    price_item_versions.build(
      reference_price: reference_price_was,
      changed_at: Time.current,
      invoice_date: last_invoice_date_was,
      quantity: last_order_quantity_was,
      total: last_total_was
    )
  end

  def record_initial_price
    price_item_versions.create!(
      reference_price: reference_price,
      changed_at: created_at,
      invoice_date: last_invoice_date,
      quantity: last_order_quantity,
      total: last_total
    )
  end
end

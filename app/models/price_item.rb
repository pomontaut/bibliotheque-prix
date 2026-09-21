class PriceItem < ApplicationRecord
  has_many :price_item_versions, -> { order(changed_at: :desc) }, dependent: :destroy

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
    price_item_versions.build(
      reference_price: reference_price_was,
      changed_at: Time.current
    )
  end

  def record_initial_price
    price_item_versions.create!(reference_price: reference_price, changed_at: created_at)
  end
end

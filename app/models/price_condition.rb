class PriceCondition < ApplicationRecord
  belongs_to :supplier
  belongs_to :price_item

  validates :negotiated_price, numericality: { greater_than_or_equal_to: 0 }
  validates :valid_from, presence: true
  validate :valid_until_after_valid_from

  scope :current, -> { where("valid_from <= ? AND (valid_until IS NULL OR valid_until >= ?)", Date.current, Date.current) }

  private

  def valid_until_after_valid_from
    return if valid_until.blank? || valid_from.blank?

    errors.add(:valid_until, "doit être après la date de début") if valid_until < valid_from
  end
end

class InvoiceLine < ApplicationRecord
  belongs_to :invoice
  belongs_to :price_item, optional: true

  validates :description, presence: true

  before_save :recompute_ratio

  # Ratio > 1 means the invoice charged more than the reference price.
  def anomalous?
    ratio.present? && (ratio < 0.9 || ratio > 1.1)
  end

  def reference_price
    return nil unless price_item

    condition = invoice.supplier.active_condition_for(price_item, on: invoice.invoice_date || Date.current)
    condition&.negotiated_price || price_item.reference_price
  end

  private

  def recompute_ratio
    self.ratio = (reference_price.present? && reference_price.positive? && unit_price.present?) ? (unit_price / reference_price).round(4) : nil
  end
end

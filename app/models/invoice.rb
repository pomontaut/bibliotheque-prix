class Invoice < ApplicationRecord
  STATUSES = %w[pending reviewed integrated].freeze

  belongs_to :supplier
  has_many :invoice_lines, dependent: :destroy
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  def parse!
    return unless file.attached?

    text = InvoiceParser.extract_text(file)
    update!(raw_text: text)

    invoice_lines.destroy_all
    InvoiceParser.extract_lines(text).each do |parsed|
      match = PriceItemMatcher.best_match(parsed[:description])
      invoice_lines.create!(
        description: parsed[:description],
        quantity: parsed[:quantity],
        unit_price: parsed[:unit_price],
        total: parsed[:total],
        price_item: match,
        matched_automatically: match.present?
      )
    end
  end

  # Updates each matched article's reference price to what this invoice actually
  # charged. PriceItem's own before_update callback records the prior price into
  # price_item_versions, so history stays consistent with manual edits.
  def integrate!
    transaction do
      invoice_lines.where.not(price_item_id: nil).find_each do |line|
        next if line.unit_price.blank?

        line.price_item.update!(reference_price: line.unit_price)
      end
      update!(status: "integrated")
    end
  end
end

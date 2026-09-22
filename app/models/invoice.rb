class Invoice < ApplicationRecord
  STATUSES = %w[pending reviewed integrated].freeze

  belongs_to :supplier
  has_many :invoice_lines, dependent: :destroy
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  def parse!
    return unless file.attached?

    text = InvoiceParser.extract_text(file)
    header = InvoiceParser.extract_header(text)
    real_supplier_name = InvoiceParser.effective_supplier_name(header[:point_of_sale])

    update!(
      raw_text: text,
      invoice_number: invoice_number.presence || header[:invoice_number],
      invoice_date: invoice_date.presence || header[:invoice_date],
      supplier: real_supplier_name.present? ? Supplier.find_or_create_by!(name: real_supplier_name) : supplier
    )

    invoice_lines.destroy_all
    InvoiceParser.extract_lines(text).each do |parsed|
      match = find_match(parsed[:article_number], parsed[:description])
      invoice_lines.create!(
        article_number: parsed[:article_number],
        description: parsed[:description],
        quantity: parsed[:quantity],
        unit_price: parsed[:unit_price],
        total: parsed[:total],
        price_item: match,
        matched_automatically: match.present?
      )
    end
  end

  def find_match(article_number, description)
    mapping = supplier.supplier_article_mappings.find_by(article_number: article_number) if article_number.present?
    mapping&.price_item || PriceItemMatcher.best_match(description)
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

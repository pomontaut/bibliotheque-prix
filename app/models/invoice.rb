class Invoice < ApplicationRecord
  STATUSES = %w[pending reviewed integrated].freeze

  # Raised by #parse! when this exact invoice (same supplier + invoice
  # number) has already been imported — never reprocess it silently, since
  # that would double the price history and inflate the ratio/anomaly
  # counters. The controller destroys the newly-uploaded duplicate and
  # points the user back at the original.
  class DuplicateError < StandardError
    attr_reader :existing_invoice

    def initialize(existing_invoice)
      @existing_invoice = existing_invoice
      super("Facture déjà importée le #{existing_invoice.created_at.strftime('%d.%m.%Y')} (n° #{existing_invoice.invoice_number})")
    end
  end

  belongs_to :supplier
  has_many :invoice_lines, dependent: :destroy
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  def parse!
    return unless file.attached?

    # Belt and suspenders: some PDFs (seen on "Récapitulatif" documents with
    # a corrupted font/encoding) extract to garbled text, so the
    # invoice_number regex below finds nothing and can't catch a re-upload.
    # The file's own checksum still can, independently of text extraction.
    duplicate_by_content = Invoice.joins(file_attachment: :blob)
                                   .where(active_storage_blobs: { checksum: file.blob.checksum })
                                   .where.not(id: id).first
    raise DuplicateError, duplicate_by_content if duplicate_by_content

    text = InvoiceParser.extract_text(file)
    header = InvoiceParser.extract_header(text)
    effective_number = invoice_number.presence || header[:invoice_number]

    if effective_number.present?
      duplicate = Invoice.where(supplier: supplier, invoice_number: effective_number).where.not(id: id).first
      raise DuplicateError, duplicate if duplicate
    end

    update!(
      raw_text: text,
      invoice_number: effective_number,
      invoice_date: invoice_date.presence || header[:invoice_date]
    )

    invoice_lines.destroy_all
    InvoiceParser.extract_lines(text).each do |parsed|
      # Each line carries its OWN point-of-sale context — a single invoice
      # can bundle several orders from different real sellers (90 of 186
      # real invoices do). Never assume the whole invoice shares one
      # supplier: resolve per line, falling back to the invoice's own
      # supplier only when this line's point of sale is blank or is HGC
      # itself under one of its several self-referential names.
      real_supplier_name = InvoiceParser.effective_supplier_name(parsed[:point_of_sale])
      line_supplier = real_supplier_name.present? ? Supplier.find_or_create_by!(name: real_supplier_name) : supplier

      is_fee = InvoiceParser.fee_article?(parsed[:article_number])
      match = is_fee ? nil : find_match(line_supplier, parsed[:article_number], parsed[:description])
      invoice_lines.create!(
        supplier: line_supplier,
        article_number: parsed[:article_number],
        description: parsed[:description],
        quantity: parsed[:quantity],
        unit_price: parsed[:unit_price],
        total: parsed[:total],
        unit: parsed[:unit],
        price_item: match,
        matched_automatically: match.present?
      )
    end
  end

  def find_match(line_supplier, article_number, description)
    if article_number.present?
      # A real article number is an exact identifier — only a known
      # SupplierArticleMapping may resolve it. Never fall back to fuzzy
      # text matching here: different article numbers with similarly-worded
      # descriptions (e.g. "swissporXPS 300 GE" vs "swissporXPS 300 GE
      # gaufré" vs "... SF lisse battues") were getting silently merged into
      # one PriceItem, corrupting its price history with unrelated
      # products. An unmapped article number returns nil — the line stays
      # unmatched until a human confirms it (or it is bootstrapped once via
      # the "Créer un article" action), which is what actually creates the
      # mapping for next time.
      return line_supplier.supplier_article_mappings.find_by(article_number: article_number)&.price_item
    end

    # No article number at all (e.g. the Gravières d'Epeisses historical
    # import, which omits it on ~70% of rows) — fuzzy text matching, scoped
    # to this line's own real supplier, is the only option left.
    PriceItemMatcher.best_match(description, scope: PriceItem.where(category: line_supplier.name))
  end

  # Updates each matched article's reference price (and known unit/quantity/
  # article number) to what this invoice actually charged. PriceItem's own
  # before_update callback records the prior price into price_item_versions,
  # so history stays consistent with manual edits.
  def integrate!
    transaction do
      invoice_lines.where.not(price_item_id: nil).find_each do |line|
        next if line.unit_price.blank?

        line.price_item.update!(
          reference_price: line.unit_price,
          unit: line.price_item.unit.presence || line.unit,
          article_number: line.price_item.article_number.presence || line.article_number,
          last_order_quantity: line.quantity,
          last_total: line.total,
          currency: currency,
          delivery_address: delivery_address,
          delivery_type: delivery_type,
          invoicing_supplier_name: supplier.name,
          last_invoice_number: invoice_number,
          last_invoice_date: invoice_date
        )
      end
      update!(status: "integrated")
    end
  end
end

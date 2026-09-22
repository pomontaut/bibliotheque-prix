# Best-effort extraction of header fields and line items from an invoice PDF.
# Only reads embedded text (no OCR) — a scanned image PDF yields no text.
#
# Line items are parsed with a backward scan from the end of each line,
# because free-text descriptions routinely contain their own numbers
# (model numbers, dimensions like "38 pièces" or "S 1122 HF") that must not
# be confused with the real quantity/price/total columns. Scanning from the
# right, past known unit abbreviations, reliably finds the numeric columns
# regardless of what the description contains. Always meant to be reviewed
# by a human before ../models/invoice.rb#integrate! is called.
class InvoiceParser
  NUMBER = /-?[\d'’]+(?:[.,]\d+)?-?/
  MERGED_QTY_UNIT = /\A(\d+(?:[.,]\d+)?)-?([A-Za-zÀ-ÿ]{1,4})\z/
  UNIT_FRAGMENT = /\A(PCE|KGR|KGM|KGB|KG|SAC|PAQ|HST|M2|M3|MT|ML|CM|AC|L|K|G|S)\z/i
  ITEM_LINE = /\A(?<pos>\d+)\s+(?<article>\d{5,})\s+/

  def self.extract_text(attachment)
    attachment.blob.open do |file|
      PDF::Reader.new(file.path).pages.map(&:text).join("\n")
    end
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    ""
  end

  def self.extract_header(text)
    {
      invoice_number: text[/Num.ro de facture\s*:\s*(\S+)/, 1],
      invoice_date: parse_date(text[/Date de facture\s*:\s*(\d{2}\.\d{2}\.\d{4})/, 1]),
      point_of_sale: text[/Point de vente\s*:\s*(.+?)(?:,|\s+\d|\n)/, 1]&.strip
    }
  end

  # HGC re-invoices goods bought directly from a manufacturer/distributor —
  # "Point de vente" then names that real seller (e.g. "Sika Schweiz AG",
  # "Mapei Suisse SA") instead of HGC itself. When that happens, the price
  # conditions really belong to that seller, not to "HGC Handel AG".
  def self.effective_supplier_name(point_of_sale)
    return nil if point_of_sale.blank?
    return nil if point_of_sale.match?(/HGC/i)

    point_of_sale
  end

  def self.extract_lines(text)
    text.to_s.each_line.filter_map { |line| parse_item_line(line) }
  end

  def self.parse_item_line(line)
    return nil if line.start_with?(" ", "\t")

    match = line.match(ITEM_LINE)
    return nil unless match

    tokens = line.rstrip.split(/\s+/)
    return nil if tokens.size < 5

    numeric_values = []
    boundary = tokens.size
    (tokens.size - 1).downto(2) do |i|
      token = tokens[i]
      if (value = numeric_value(token))
        numeric_values.unshift(value)
        boundary = i
      elsif (merged = token.match(MERGED_QTY_UNIT))
        numeric_values.unshift(numeric_value(merged[1]))
        boundary = i
      elsif token.match?(UNIT_FRAGMENT)
        boundary = i
      else
        break
      end
    end
    return nil if numeric_values.size < 2

    description = tokens[2...boundary].join(" ")
    return nil if description.blank?

    quantity = numeric_values.first
    total = numeric_values.last
    unit_price = if numeric_values.size >= 3
      numeric_values[1]
    elsif quantity.present? && !quantity.zero?
      (total / quantity).round(4)
    else
      total
    end

    { article_number: match[:article], description: description, quantity: quantity, unit_price: unit_price, total: total }
  end

  def self.numeric_value(token)
    return nil unless token.match?(/\A#{NUMBER}\z/)

    cleaned = token.delete("' ’")
    negative = cleaned.end_with?("-") || cleaned.start_with?("-")
    cleaned = cleaned.delete_suffix("-").delete_prefix("-")
    cleaned = cleaned.include?(",") && !cleaned.include?(".") ? cleaned.tr(",", ".") : cleaned.delete(",")
    value = BigDecimal(cleaned)
    negative ? -value : value
  rescue ArgumentError
    nil
  end

  def self.parse_date(raw)
    return nil if raw.blank?

    Date.strptime(raw, "%d.%m.%Y")
  rescue ArgumentError
    nil
  end
end

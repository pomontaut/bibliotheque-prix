# Best-effort extraction of line items from an invoice PDF: this only reads
# embedded text (no OCR), and the regex heuristic below assumes a line ends
# with "quantity unit_price total". Always meant to be reviewed by a human
# before ../models/invoice.rb#integrate! is called.
class InvoiceParser
  NUMBER = /-?[\d'’]+(?:[.,]\d+)?/

  def self.extract_text(attachment)
    attachment.blob.open do |file|
      PDF::Reader.new(file.path).pages.map(&:text).join("\n")
    end
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    ""
  end

  def self.extract_lines(text)
    text.to_s.each_line.filter_map do |line|
      line = line.strip
      next if line.blank?

      match = line.match(/\A(?<description>.+?)\s+(?<quantity>#{NUMBER})\s+(?<unit_price>#{NUMBER})\s+(?<total>#{NUMBER})\s*\z/)
      next unless match

      description = match[:description].strip
      next if description.blank? || description.length < 3

      {
        description: description,
        quantity: parse_number(match[:quantity]),
        unit_price: parse_number(match[:unit_price]),
        total: parse_number(match[:total])
      }
    end
  end

  def self.parse_number(raw)
    cleaned = raw.to_s.delete("' ’")
    cleaned = if cleaned.include?(",") && !cleaned.include?(".")
      cleaned.tr(",", ".")
    else
      cleaned.delete(",")
    end
    BigDecimal(cleaned)
  rescue ArgumentError
    nil
  end
end

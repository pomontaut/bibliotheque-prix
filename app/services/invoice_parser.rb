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
  NUMBER = /-?[\d',’]+(?:\.\d+)?-?/
  UNIT_FRAGMENT = /\A(PCE|KGR|KGM|KGB|KG|SAC|PAQ|HST|M2|M3|MT|ML|CM|AC|L|K|G|S)\z/i
  MERGED_QTY_UNIT = /\A(\d+(?:[.,]\d+)?)-?(PCE|KGR|KGM|KGB|KG|SAC|PAQ|HST|M2|M3|MT|ML|CM|AC|L|K|G|S)\z/i
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
      invoice_date: parse_date(text[/Date de facture\s*:\s*(\d{2}\.\d{2}\.\d{4})/, 1])
    }
  end

  # HGC re-invoices goods bought directly from a manufacturer/distributor —
  # "Point de vente" then names that real seller (e.g. "Sika Schweiz AG",
  # "Mapei Suisse SA") instead of HGC itself. When that happens, the price
  # conditions really belong to that seller, not to HGC.
  #
  # HGC itself appears under several self-referential names depending on the
  # invoice's age/template — "HGC Handel AG" (legal/payment name), "HGC
  # Commerce SA" (a retail point of sale) and "HG COMMERCIALE" (older
  # template, pre-rename) have all been observed. Match the "HG"/"HGC" word
  # itself rather than a single exact name so any of these stay grouped
  # together instead of splintering into separate Suppliers.
  def self.effective_supplier_name(point_of_sale)
    return nil if point_of_sale.blank?
    return nil if point_of_sale.match?(/\bHGC?\b/i)

    point_of_sale
  end

  POINT_OF_SALE_LINE = /Point de vente\s*:\s*(.+?)(?:,|\s+\d|\n)/
  NET_AMOUNT_LINE = /Montant hors TVA\s+(.+)/
  MAX_CONTINUATION_LOOKAHEAD = 6

  # A single invoice document can bundle several different orders, each
  # under its OWN "Point de vente:" line (observed on 90 of 186 real
  # invoices) — e.g. one invoice with a Mapei section followed later by an
  # HGC section. Attributing the whole invoice to whichever point of sale
  # appears first would silently mislabel every line item after the first
  # section switch. So this tracks the current point-of-sale as it scans
  # down the text and tags each item line with the one in effect *at that
  # line*, not a single value for the whole document.
  def self.extract_lines(text)
    # Some PDFs render each line's text twice at the same position (a
    # rendering artifact, not two real rows — observed within a single
    # page, same line, identical down to the last digit). Collapsing
    # consecutive exact duplicates is safe: a real document never has two
    # genuinely distinct positions with byte-for-byte identical text.
    lines = text.to_s.each_line.each_with_object([]) { |l, acc| acc << l unless l == acc.last }
    current_point_of_sale = nil
    results = []

    lines.each_with_index do |line, i|
      if (m = line.match(POINT_OF_SALE_LINE))
        current_point_of_sale = m[1].strip
        next
      end

      parsed = parse_item_line(line)
      next unless parsed

      # The item line itself only ever shows the GROSS unit price/total,
      # before any "Rabais"/"Supplément net"/"Frais" line that follows it
      # adjusts the amount. The true price actually paid only appears on
      # the block's "Montant hors TVA" line (1 number = net total only, 2
      # numbers = net unit price then net total) — use that whenever
      # present instead of the gross figures, since that is what the price
      # library and ratio calculations must track.
      net = net_amount_after(lines, i, parsed[:quantity])
      parsed = parsed.merge(unit_price: net[:unit_price], total: net[:total]) if net

      results << parsed.merge(point_of_sale: current_point_of_sale)
    end

    results
  end

  def self.net_amount_after(lines, item_index, quantity)
    (item_index + 1..[ item_index + MAX_CONTINUATION_LOOKAHEAD, lines.size - 1 ].min).each do |j|
      continuation = lines[j]
      break if continuation.match?(ITEM_LINE) || continuation.match?(POINT_OF_SALE_LINE)

      next unless (m = continuation.match(NET_AMOUNT_LINE))

      numbers = m[1].scan(/#{NUMBER}/).filter_map { |t| numeric_value(t) }
      case numbers.size
      when 0 then return nil
      when 1
        total = numbers.first
        unit_price = quantity.present? && !quantity.zero? ? (total / quantity).round(4) : total
        return { unit_price: unit_price, total: total }
      else
        return { unit_price: numbers[0], total: numbers[1] }
      end
    end
    nil
  end

  # HGC's own numbering: article numbers starting with "2" are administrative
  # surcharges (Taxe RPLP, Frais de transport, Emballage...), never a
  # purchasable material — they must never become (or match) a PriceItem.
  def self.fee_article?(article_number)
    article_number.to_s.match?(/\A2\d{5,}\z/)
  end

  def self.parse_item_line(line)
    # Leading whitespace alone doesn't distinguish a real item line from a
    # "Rabais"/continuation sub-line — some invoice templates indent every
    # line uniformly, item lines included. ITEM_LINE itself already rejects
    # continuation lines (their second token, e.g. "E-26179" or "-1070", is
    # never a plain 5+ digit article number), so stripping first is safe.
    stripped = line.strip
    match = stripped.match(ITEM_LINE)
    return nil unless match

    tokens = stripped.split(/\s+/)
    return nil if tokens.size < 5

    # Exactly 4 numeric columns exist on a real item line (quantity, unit
    # price, the "UP" reference quantity, total) — stop as soon as 4 are
    # found. Without this cap, a stray single-digit footnote marker before
    # the real quantity (e.g. "IBC 1000        1-     1'070 KG ...", the "1-"
    # being some internal reference, not data) gets swept in as a 5th
    # "quantity" and shifts quantity/unit_price off by one column.
    numeric_values = []
    boundary = tokens.size
    (tokens.size - 1).downto(2) do |i|
      break if numeric_values.size >= 4

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
    # A real item always names something — purely numeric "descriptions"
    # are the Swiss QR-bill payment slip's reference number block ("27
    # 47100 00000 10157 09613 74035...", repeated for its two copies),
    # which otherwise satisfies pos+article+4-trailing-numbers by accident.
    return nil if description.blank? || !description.match?(/[a-zA-ZÀ-ÿ]/)

    quantity = numeric_values.first
    total = numeric_values.last
    unit_price = if numeric_values.size >= 3
      numeric_values[1]
    elsif quantity.present? && !quantity.zero?
      (total / quantity).round(4)
    else
      total
    end

    { article_number: match[:article], description: description, quantity: quantity, unit_price: unit_price, total: total, unit: unit_after(tokens, boundary) }
  end

  # The unit code sits right after the quantity token — either merged into it
  # ("6SAC") or as one or two short fragments split by the PDF's spacing
  # ("K G" instead of "KG").
  def self.unit_after(tokens, boundary)
    qty_token = tokens[boundary]
    if (merged = qty_token.match(MERGED_QTY_UNIT))
      return merged[2].upcase
    end

    parts = []
    (boundary + 1).upto([ boundary + 2, tokens.size - 1 ].min) do |i|
      break unless tokens[i]&.match?(UNIT_FRAGMENT)

      parts << tokens[i].upcase
    end
    parts.join.presence
  end

  def self.numeric_value(token)
    return nil unless token.match?(/\A#{NUMBER}\z/)

    # Both thousands-separator conventions seen in the real corpus use "."
    # for the decimal point ("1'070 KG" / "5'478.40" with an apostrophe, or
    # "1,070 KG" / "5,478.40" with a comma) — neither invoice source uses a
    # comma as a decimal separator, so the comma is always thousands
    # grouping here and must simply be dropped, never converted to ".".
    cleaned = token.delete("' ’,")
    negative = cleaned.end_with?("-") || cleaned.start_with?("-")
    cleaned = cleaned.delete_suffix("-").delete_prefix("-")
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

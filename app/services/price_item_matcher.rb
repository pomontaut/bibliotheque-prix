# Fuzzy-matches a raw invoice line description against the price library
# using word overlap. Deliberately simple (no external NLP dependency) —
# it is a suggestion the reviewer confirms or corrects, not a final answer.
class PriceItemMatcher
  MIN_SCORE = 0.34

  def self.best_match(description)
    words = normalize(description)
    return nil if words.empty?

    best = PriceItem.find_each.map { |item| [item, score(words, normalize(item.name))] }
                     .max_by { |_, score| score }

    best && best.last >= MIN_SCORE ? best.first : nil
  end

  def self.score(words_a, words_b)
    return 0.0 if words_a.empty? || words_b.empty?

    intersection = (words_a & words_b).size
    union = (words_a | words_b).size
    union.zero? ? 0.0 : intersection.to_f / union
  end

  def self.normalize(text)
    I18n.transliterate(text.to_s).downcase
        .gsub(/[^a-z0-9\s]/, " ")
        .split
        .reject { |w| w.length < 3 }
  end
end

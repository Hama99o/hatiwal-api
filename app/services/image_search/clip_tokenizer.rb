# Sell with a photo (docs/SELL_WITH_PHOTO.md): CLIP's text tokenizer, in Ruby.
#
# It turns an English prompt ("a photo of a mobile phone") into the token ids
# CLIP's text model reads. It is the byte-level BPE of the model's own
# vocab.json + merges.txt (same revision as the model), with the steps of its
# tokenizer.json: NFC, collapse whitespace, lowercase, split into words, then
# BPE each word with "</w>" on its last symbol. A gem (tokenizers) would do the
# same with a Rust extension; the prompts are a few dozen short English
# phrases embedded once per process, so this stays dependency-free.
#
# Checked against Hugging Face `tokenizers` on every prompt we use
# (spec/services/image_search/clip_tokenizer_spec.rb holds the reference ids).
module ImageSearch
  class ClipTokenizer
    START_OF_TEXT = 49_406
    END_OF_TEXT   = 49_407
    MAX_TOKENS    = 77
    WORD = /<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+/

    def initialize(vocab_path, merges_path)
      @vocab = JSON.parse(File.read(vocab_path))
      merges = File.readlines(merges_path, chomp: true).drop(1).reject(&:empty?)
      @ranks = merges.each_with_index.to_h { |line, i| [ line.split(" ", 2), i ] }
      @byte_chars = self.class.bytes_to_unicode
      @cache = {}
    end

    # text -> Array of ids: [START_OF_TEXT, ..., END_OF_TEXT], at most MAX_TOKENS.
    def encode(text)
      normalized = text.unicode_normalize(:nfc).gsub(/\s+/, " ").downcase
      ids = normalized.scan(WORD).flat_map do |word|
        chars = word.bytes.map { |b| @byte_chars[b] }.join
        bpe(chars).map { |token| @vocab.fetch(token) { END_OF_TEXT } }
      end
      [ START_OF_TEXT, *ids.first(MAX_TOKENS - 2), END_OF_TEXT ]
    end

    # GPT-2's byte <-> printable character table, as CLIP uses it.
    def self.bytes_to_unicode
      printable = (33..126).to_a + (161..172).to_a + (174..255).to_a
      extra = 0
      (0..255).to_h do |b|
        if printable.include?(b)
          [ b, b.chr(Encoding::UTF_8) ]
        else
          extra += 1
          [ b, (255 + extra).chr(Encoding::UTF_8) ]
        end
      end
    end

    private

    def bpe(chars)
      @cache[chars] ||= begin
        symbols = chars.chars
        symbols[-1] = "#{symbols[-1]}</w>"
        loop do
          pairs = symbols.each_cons(2).to_a
          best = pairs.min_by { |pair| @ranks.fetch(pair, Float::INFINITY) }
          break if best.nil? || !@ranks.key?(best)

          merged = []
          i = 0
          while i < symbols.size
            if i < symbols.size - 1 && symbols[i] == best[0] && symbols[i + 1] == best[1]
              merged << (best[0] + best[1])
              i += 2
            else
              merged << symbols[i]
              i += 1
            end
          end
          symbols = merged
        end
        symbols
      end
    end
  end
end

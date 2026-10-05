require "rails_helper"

# Every app string exists in en, ps, fa AND ur. Urdu is hidden in the clients
# for now (owner, 2026-10-05) but is still translated, so it can come back at
# once. Devise's own en-only file is excluded.
RSpec.describe "Locale coverage" do
  LOCALES = %w[en ps fa ur].freeze

  def flatten(hash, prefix = nil)
    hash.flat_map do |k, v|
      key = [ prefix, k ].compact.join(".")
      v.is_a?(Hash) ? flatten(v, key) : [ key ]
    end
  end

  # { "en" => Set[...keys], ... } built from config/locales, file by file:
  # "foo.ps.yml" and "ps.yml" both count for ps.
  def keys_by_locale
    files = Dir[Rails.root.join("config/locales/*.yml")].reject { |f| File.basename(f).start_with?("devise.") }
    files.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |file, acc|
      YAML.load_file(file, aliases: true).each do |locale, tree|
        acc[locale].merge(flatten(tree)) if LOCALES.include?(locale) && tree.is_a?(Hash)
      end
    end
  end

  LOCALES.excluding("en").each do |locale|
    it "#{locale} has every en key" do
      all = keys_by_locale
      # "hello" is the Rails generator sample, never shown.
      missing = (all["en"] - all[locale] - [ "hello" ]).to_a.sort
      expect(missing).to eq([]), "missing in #{locale}: #{missing.first(20).join(', ')}"
    end
  end
end

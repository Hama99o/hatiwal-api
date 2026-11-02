class ApplicationSerializer < Blueprinter::Base
  # Money as a JSON NUMBER. A numeric column is a BigDecimal, and Rails/Blueprinter
  # write a BigDecimal as a STRING ("560000.0") — the apps' price formatter has
  # refused non-numbers since mobile 1.1.7, so every live price rendered blank
  # (P0, 2026-10-27). precision 12 / scale 2 fits a Float exactly enough for
  # display (< 2^53). nil stays nil.
  def self.money(value)
    value&.to_f
  end

  def self.model_name
    ActiveModel::Name.new(self, nil, name.delete_suffix("Serializer"))
  end
end

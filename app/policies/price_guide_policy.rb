# IDEA-4: the price guide is aggregates only — anyone (a guest too) may read it.
class PriceGuidePolicy < ApplicationPolicy
  def show?
    true
  end
end

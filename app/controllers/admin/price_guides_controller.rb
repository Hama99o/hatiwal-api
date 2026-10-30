# "Price guide" (IDEA-4): the buckets against the threshold, read-only.
module Admin
  class PriceGuidesController < Admin::ApplicationController
    include Administrate::Punditize

    private

    def policy_namespace
      [ :admin ]
    end

    def pundit_user
      current_admin_user
    end

    def default_sorting_attribute
      :sales_count
    end

    def default_sorting_direction
      :desc
    end
  end
end

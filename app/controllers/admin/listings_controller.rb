module Admin
  class ListingsController < Admin::ApplicationController
    filter :status, :select, options: -> { Listing.statuses.keys }
    filter :condition, :select, options: -> { Listing.conditions.keys }
    # Categories are stored per locale (name_en / name_ps / name_fa / name_ur) —
    # there is no plain `name` column. The admin is English, so the picker shows
    # name_en and falls back to the slug when a category has no English name.
    #
    # A :scope, not a plain :select on category_id: listings attach to
    # SUBcategories, so picking a parent ("Electronics") has to include its
    # children — Listing.by_category already does exactly that.
    filter :category, :scope, label: "Category",
           options: lambda {
             Category.order(:name_en).pluck(:name_en, :slug, :id)
                     .map { |en, slug, id| [ en.presence || slug, id ] }
           },
           scope: ->(rel, v) { rel.by_category(v.to_i) }
    # Listings have no city column; `location` is the free-text place the seller
    # typed, which is where the city lives.
    filter :location, :text, label: "City / location"
    filter :price, :number_range
    filter :reported, :scope, options: -> { %w[yes] }, scope: lambda { |rel, v|
      next rel unless v == "yes"

      rel.where(id: Report.where(reportable_type: Listing.name).select(:reportable_id))
    }
    # Expiry is a timestamp, not a status, so a listing can be `active` AND past
    # its expires_at — which is exactly the set an operator wants to find.
    # expires_at is nullable (no expiry), so "no" must include NULL — reuse the
    # model's not_expired, which does; a bare range comparison would drop them.
    filter :expired, :scope, options: -> { %w[yes no] }, scope: lambda { |rel, v|
      v == "yes" ? rel.where(expires_at: ...Time.current) : rel.not_expired
    }
    filter :created, :date_range, column: :created_at, label: "Posted"

    # Take down (soft-remove) a listing — hides it from the public feed/detail
    # page. Restore reverses it.
    def take_down
      listing = find_resource(params[:id])
      listing.take_down!(reason: params[:removed_reason])
      log_admin_action("take_down_listing", target: listing, details: listing.removed_reason)
      redirect_to [ namespace, listing ], notice: "Listing taken down."
    end

    def restore
      listing = find_resource(params[:id])
      listing.restore!
      log_admin_action("restore_listing", target: listing)
      redirect_to [ namespace, listing ], notice: "Listing restored."
    end

    # Override this method to specify custom lookup behavior.
    # This will be used to set the resource for the `show`, `edit`, and `update`
    # actions.
    #
    # def find_resource(param)
    #   Foo.find_by!(slug: param)
    # end

    # The result of this lookup will be available as `requested_resource`

    # Override this if you have certain roles that require a subset
    # this will be used to set the records shown on the `index` action.
    #
    # def scoped_resource
    #   if current_user.super_admin?
    #     resource_class
    #   else
    #     resource_class.with_less_stuff
    #   end
    # end

    # Override `resource_params` if you want to transform the submitted
    # data before it's persisted. For example, the following would turn all
    # empty values into nil values. It uses other APIs such as `resource_class`
    # and `dashboard`:
    #
    # def resource_params
    #   params.require(resource_class.model_name.param_key).
    #     permit(dashboard.permitted_attributes(action_name)).
    #     transform_values { |value| value == "" ? nil : value }
    # end

    # See https://administrate-demo.herokuapp.com/customizing_controller_actions
    # for more information
  end
end

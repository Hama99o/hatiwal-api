module Admin
  class ListingsController < Admin::ApplicationController
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

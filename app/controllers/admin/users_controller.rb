module Admin
  class UsersController < Admin::ApplicationController
    # Block: ban the account and store the reason shown to the user. Unblock:
    # restore to active and clear the reason. Both reuse the existing status
    # enum, so a blocked account is rejected by the API immediately.
    def block
      user = find_resource(params[:id])
      user.update!(status: :banned, block_reason: params[:block_reason].presence)
      redirect_to [ namespace, user ], notice: "#{user.full_name} has been blocked."
    end

    def unblock
      user = find_resource(params[:id])
      user.update!(status: :active, block_reason: nil)
      redirect_to [ namespace, user ], notice: "#{user.full_name} has been unblocked."
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

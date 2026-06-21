module Admin
  # Manage staff (admin) accounts: list, create, edit, delete.
  class AdminUsersController < Admin::ApplicationController
    def create
      super
      log_admin_action("create_admin", target: requested_resource) if requested_resource&.persisted?
    end

    def update
      super
      # previous_changes is populated only on a successful save.
      log_admin_action("update_admin", target: requested_resource) if requested_resource&.previous_changes&.any?
    end

    # Guardrails: an admin can't lock everyone out by deleting themselves or the
    # last remaining account.
    def destroy
      admin = find_resource(params[:id])

      if admin == current_admin_user
        return redirect_to([ namespace, admin ], alert: "You can't delete your own admin account.")
      end
      if AdminUser.count <= 1
        return redirect_to([ namespace, admin ], alert: "You can't delete the last admin account.")
      end

      email = admin.email
      admin.destroy
      log_admin_action("delete_admin", details: email)
      redirect_to admin_admin_users_path, notice: "Admin account deleted."
    end

    private

    # Permit only safe fields. On edit a blank password means "keep current" —
    # drop it so Devise doesn't try to set an empty (invalid) password.
    def resource_params
      permitted = params.require(:admin_user).permit(:name, :email, :password)
      permitted.delete(:password) if permitted[:password].blank?
      permitted
    end
  end
end

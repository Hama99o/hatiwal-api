module Admin
  # Read-only listing of warnings. They are issued from the user show page
  # (Admin::UsersController#warn), so there are no new/create/edit actions.
  class UserWarningsController < Admin::ApplicationController
  end
end

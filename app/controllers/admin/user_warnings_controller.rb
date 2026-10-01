module Admin
  # Read-only listing of warnings. They are issued from the user show page
  # (Admin::UsersController#warn), so there are no new/create/edit actions.
  class UserWarningsController < Admin::ApplicationController
    filter :category, :select, options: -> { UserWarning.categories.keys }
    # UserWarning already models active/expired as scopes; reuse them rather than
    # re-expressing the expiry comparison here.
    filter :state, :scope, options: -> { %w[active expired] }, scope: lambda { |rel, v|
      v == "active" ? rel.active : rel.expired
    }
    filter :created, :date_range, column: :created_at, label: "Issued"
  end
end

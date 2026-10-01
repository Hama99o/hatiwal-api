# The user filters, declared ONCE and shared by the users index and bulk email
# (Admin::MessagesController). "Filter users, then email them" only means
# something if the list an admin filters is the very relation that receives,
# so there is one definition, not two that can drift.
module Admin
  module UserFilterSet
    extend ActiveSupport::Concern

    included do
      # Enum values are READ FROM THE MODEL, never written out here — a filter that
      # offers a value the enum does not have is a dead button, and the enum is free
      # to change without anyone remembering this file.
      filter :status, :select, options: -> { User.statuses.keys }
      filter :preferred_language, :select,
             options: -> { User::SUPPORTED_LANGUAGES },
             label: "Language"
      filter :verified, :boolean
      filter :seller_mode, :boolean, label: "Seller"
      filter :auto_blocked, :boolean, label: "Auto-blocked"
      # `verified` is the trust BADGE an admin toggles; `confirmed` is whether the
      # email address was ever proven. Deliberately two different filters.
      filter :confirmed, :scope, options: -> { %w[yes no] }, scope: lambda { |rel, v|
        v == "yes" ? rel.where.not(confirmed_at: nil) : rel.where(confirmed_at: nil)
      }
      filter :pending_deletion, :scope, options: -> { %w[yes no] },
             label: "Pending deletion", scope: lambda { |rel, v|
               if v == "yes"
                 rel.where.not(deletion_scheduled_at: nil).where(deleted_at: nil)
               else
                 rel.where(deletion_scheduled_at: nil)
               end
             }
      filter :deleted, :scope, options: -> { %w[yes no] }, scope: lambda { |rel, v|
        v == "yes" ? rel.where.not(deleted_at: nil) : rel.where(deleted_at: nil)
      }
      filter :city, :text
      filter :province, :text
      filter :created, :date_range, column: :created_at, label: "Joined"
    end
  end
end

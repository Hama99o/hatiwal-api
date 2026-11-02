# "Prohibited terms" (owner, 2026-10-13): the words that open a flag. Plain
# Administrate CRUD, authorized with Admin::ProhibitedTermPolicy, every change
# written to the audit log.
module Admin
  class ProhibitedTermsController < Admin::ApplicationController
    include Administrate::Punditize

    filter :category, :select, options: -> { ProhibitedTerm.categories.keys }
    filter :locale, :select, label: "Language", options: -> { ProhibitedTerm.locales.keys }

    def create
      super { |term| log_admin_action("prohibited_term_create", target: term, details: summary(term)) }
    end

    def update
      super
      log_admin_action("prohibited_term_update", target: requested_resource, details: summary(requested_resource)) if response.redirect?
    end

    def destroy
      details = summary(requested_resource)
      super
      log_admin_action("prohibited_term_destroy", details: details) if requested_resource.destroyed?
    end

    private

    def policy_namespace
      [ :admin ]
    end

    def pundit_user
      current_admin_user
    end

    def default_sorting_attribute
      :category
    end

    def default_sorting_direction
      :asc
    end

    def summary(term)
      "#{term.term} (#{term.locale}, #{term.category})"
    end
  end
end

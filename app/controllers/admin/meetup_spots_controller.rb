# "Meetup spots" (IDEA-6): the busy public places the apps suggest for a
# meetup. Plain Administrate CRUD, authorized with Admin::MeetupSpotPolicy,
# every change written to the audit log. A draft row "Needs local check".
module Admin
  class MeetupSpotsController < Admin::ApplicationController
    include Administrate::Punditize

    filter :city_key, :select, label: "City", options: -> { MeetupSpot.distinct.order(:city_key).pluck(:city_key) }

    def create
      super { |spot| log_admin_action("meetup_spot_create", target: spot, details: summary(spot)) }
    end

    def update
      super
      log_admin_action("meetup_spot_update", target: requested_resource, details: summary(requested_resource)) if response.redirect?
    end

    def destroy
      details = summary(requested_resource)
      super
      log_admin_action("meetup_spot_destroy", details: details) if requested_resource.destroyed?
    end

    private

    def policy_namespace
      [ :admin ]
    end

    def pundit_user
      current_admin_user
    end

    def default_sorting_attribute
      :city_key
    end

    def default_sorting_direction
      :asc
    end

    def summary(spot)
      "#{spot.name_en} (#{spot.city_key}, active=#{spot.active}, needs_local_check=#{spot.needs_local_check})"
    end
  end
end

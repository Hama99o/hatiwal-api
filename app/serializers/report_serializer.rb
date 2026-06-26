class ReportSerializer < ApplicationSerializer
  fields :id, :reason, :status, :description, :created_at

  view :list do
    field(:reportable_type) { |r| r.reportable_type }
    field(:reportable_id)   { |r| r.reportable_id }
    field(:reportable_label) do |r|
      reportable = r.reportable
      if reportable.nil?
        "[deleted]"
      elsif reportable.is_a?(Listing)
        reportable.title.presence || "[deleted]"
      elsif reportable.is_a?(User)
        reportable.full_name.presence || "[deleted]"
      else
        "[deleted]"
      end
    end
  end
end

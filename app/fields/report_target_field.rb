require "administrate/field/polymorphic"

# A report's target. Listings, users and shops render as Administrate's usual
# link. A reported voice message (1.2.1) has no admin page of its own (the admin
# "messages" pages are outreach, a different thing), so it is plain text here;
# the report page's triage panel plays it.
class ReportTargetField < Administrate::Field::Polymorphic
  def voice_message?
    data.is_a?(Message)
  end

  def voice_label
    "Voice message ##{data.id}"
  end
end

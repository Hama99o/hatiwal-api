# OFFLINE phase 2a (docs/OFFLINE_MODE.md §7.2) — remembers when and by whom
# each user-editable field was last changed, in a `field_edits` jsonb column:
#   { "price" => { "at" => "2026-10-26T14:02:00Z", "by" => 12 } }
# Recorded on EVERY save that changes one of them (app, web, admin), with the
# record's `acting_user` (nil = a system change). An edit queued offline that
# meets a newer value reads it here to say who changed it, and when.
module FieldEdits
  extend ActiveSupport::Concern

  class_methods do
    def tracks_field_edits(*fields)
      const_set(:TRACKED_EDIT_FIELDS, fields.map(&:to_s).freeze)
      before_save :record_field_edits
    end
  end

  # {at:, by_name:} for a field, or the record's last update when never tracked.
  def last_field_edit(field)
    edit = field_edits[field.to_s]
    return { at: updated_at, by_name: nil } unless edit

    { at: Time.zone.parse(edit["at"]), by_name: User.find_by(id: edit["by"])&.full_name }
  end

  private

  # Edits only: on create every field is "changed", and a field never edited
  # since falls back to the record's own updated_at.
  def record_field_edits
    return if new_record?

    changed = self.class::TRACKED_EDIT_FIELDS & changed_attributes.keys
    return if changed.empty?

    stamp = { "at" => Time.current.iso8601, "by" => acting_user&.id }
    self.field_edits = field_edits.merge(changed.index_with { stamp })
  end
end

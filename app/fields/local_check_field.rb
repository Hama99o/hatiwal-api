require "administrate/field/boolean"

# IDEA-6: a meetup spot's `needs_local_check`, shown as a badge nobody can miss
# on the list (a draft row stays hidden from the apps until it is cleared).
class LocalCheckField < Administrate::Field::Boolean
  def needed?
    data == true
  end
end

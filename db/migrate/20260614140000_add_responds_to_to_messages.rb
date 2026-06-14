class AddRespondsToToMessages < ActiveRecord::Migration[8.1]
  def change
    # Links a meetup accept/decline response to the specific proposal message it
    # answers, so one response never affects another proposal.
    add_reference :messages, :responds_to,
                  null: true,
                  foreign_key: { to_table: :messages }
  end
end

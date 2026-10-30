class ReportPolicy < ApplicationPolicy
  def index?  = true
  # The Support account is staff, not a member: there is nothing to moderate.
  # A draft is nobody's to see but its seller's, so it is not reportable either:
  # the report list echoes the listing's title (IDOR sweep 2026-10-13).
  # A voice message (1.2.1) only from inside its chat: no one else may even
  # learn that it exists.
  def create? = !support_account? && !draft_listing? && !message_outside_the_chat?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(reporter: user)
  end

  private

  def support_account? = record.reportable.is_a?(User) && record.reportable.support_account?
  def draft_listing? = record.reportable.is_a?(Listing) && record.reportable.draft?
  def message_outside_the_chat? = record.reportable.is_a?(Message) && !record.reportable.conversation.participant?(user)
end

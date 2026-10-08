# VER-1 status card. NEVER exposes a document: only how many photos were sent.
# spec/requests/api/v1/verification_requests_spec.rb asserts no URL, blob or
# signed id appears anywhere in the payload.
class VerificationStatusSerializer < ApplicationSerializer
  field(:status, &:state)
  field :verified_since
  field :missing
  # Private to the applicant (opts[:private_details]; false for a shop's staff
  # and managers — review 2026-10-08). Absent option = private (the applicant).
  field(:reason) { |s, opts| opts[:private_details] == false ? nil : s.reason }
  field(:name_changed, &:name_changed?)
  field(:request) do |status, opts|
    r = status.shown_request
    next nil unless r

    mine = opts[:private_details] != false
    {
      id: r.id,
      status: r.status,
      document_type: r.document_type,
      name_on_document: mine ? r.name_on_document : nil,
      document_last4: mine ? r.document_last4 : nil,
      files_count: r.files_count,
      # The photos were deleted FILES_KEPT_FOR after the decision: the card says
      # so instead of inferring it from files_count 0.
      files_purged: r.files_purged_at.present?,
      reason_code: mine ? r.reason_code : nil,
      created_at: r.created_at,
      decided_at: r.decided_at
    }
  end
end

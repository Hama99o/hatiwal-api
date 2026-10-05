# VER-1 status card. NEVER exposes a document: only how many photos were sent.
# spec/requests/api/v1/verification_requests_spec.rb asserts no URL, blob or
# signed id appears anywhere in the payload.
class VerificationStatusSerializer < ApplicationSerializer
  field(:status, &:state)
  field :verified_since
  field :missing
  field :reason
  field(:request) do |status|
    r = status.shown_request
    next nil unless r

    {
      id: r.id,
      status: r.status,
      document_type: r.document_type,
      name_on_document: r.name_on_document,
      document_last4: r.document_last4,
      files_count: r.files_count,
      reason_code: r.reason_code,
      created_at: r.created_at,
      decided_at: r.decided_at
    }
  end
end

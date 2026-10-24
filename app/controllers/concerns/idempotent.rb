# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1) — `Idempotency-Key` on writes.
#
#   class Api::V1::My::ListingsController < Api::V1::BaseController
#     include Idempotent
#     idempotent :create, :update, :destroy
#
# A request WITHOUT the header (every 1.1.x app) runs exactly as before.
# With it:
#   1. a row (user, key) is INSERTed first, `in_progress` — the unique index
#      makes two concurrent requests with one key safe;
#   2. the action runs;
#   3. its answer (code + JSON body) is stored, `completed`.
# A repeat of the key:
#   - completed → the stored answer, same code and body, and nothing runs again
#     (header `Idempotent-Replayed: true`);
#   - still in progress → 409 `idempotency_in_progress`: the client retries later;
#   - a DIFFERENT request under the same key → 422 `idempotency_key_reused`.
# A 5xx or an exception is NOT kept: the row is removed so a retry can run.
#
# The fingerprint is the method, the path and the PARAMETERS — not the raw body:
# a multipart retry carries a new random boundary, so the raw bytes differ for
# the same request. Uploaded files count by name and size.
module Idempotent
  extend ActiveSupport::Concern

  class_methods do
    def idempotent(*actions)
      around_action :with_idempotency_key, only: actions
    end
  end

  private

  def with_idempotency_key
    key = request.headers[IdempotencyKey::HEADER]
    return yield if key.blank? || current_user.nil?

    unless IdempotencyKey.valid_key?(key)
      return render_unprocessable_entity("Idempotency-Key must be 8 to 64 letters, digits, - or _",
                                         code: "idempotency_key_invalid")
    end

    fingerprint = idempotency_fingerprint
    record = claim_idempotency_key(key, fingerprint)
    return unless record # answered from (or refused by) an earlier request

    run_and_store(record) { yield }
  end

  # The INSERT that wins the race, or nil after rendering the earlier request's answer.
  def claim_idempotency_key(key, fingerprint)
    # A savepoint: the losing INSERT must not abort an enclosing transaction.
    IdempotencyKey.transaction(requires_new: true) do
      IdempotencyKey.create!(user: current_user, key: key, request_fingerprint: fingerprint)
    end
  rescue ActiveRecord::RecordNotUnique
    existing = IdempotencyKey.find_by!(user: current_user, key: key)
    if existing.request_fingerprint != fingerprint
      render_unprocessable_entity("This Idempotency-Key was already used for a different request",
                                  code: "idempotency_key_reused")
    elsif existing.in_progress?
      render_ok({ error: "The first request with this Idempotency-Key is still running", code: "idempotency_in_progress" },
                status: :conflict)
    else
      replay_idempotent_response(existing)
    end
    nil
  end

  def run_and_store(record)
    yield
    if response.status >= 500
      record.destroy
    else
      record.update!(status: :completed, response_code: response.status, response_body: stored_body)
    end
  rescue StandardError
    record.destroy
    raise
  end

  def stored_body
    return nil if response.body.blank?

    JSON.parse(response.body)
  rescue JSON::ParserError
    nil
  end

  def replay_idempotent_response(existing)
    response.set_header("Idempotent-Replayed", "true")
    if existing.response_body.nil?
      head existing.response_code
    else
      render_ok(existing.response_body, status: existing.response_code)
    end
  end

  def idempotency_fingerprint
    payload = [ request.request_method, request.path, canonical_params(request.request_parameters) ]
    Digest::SHA256.hexdigest(payload.to_json)
  end

  # Sorted keys; an uploaded file is its name and size (never its bytes).
  def canonical_params(value)
    case value
    when Hash, ActionController::Parameters
      value.to_h.sort_by { |k, _| k.to_s }.to_h { |k, v| [ k.to_s, canonical_params(v) ] }
    when Array then value.map { |v| canonical_params(v) }
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile
      "file:#{value.original_filename}:#{value.size}"
    else value
    end
  end
end

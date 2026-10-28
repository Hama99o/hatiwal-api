# OFFLINE §10.1 — RSwag: the Idempotency-Key header, documented the same way on every write
# that honours it (`idempotent :…` in its controller). Inside a `post`/`put`/`patch`/`delete`
# block of a swagger spec: `idempotency_key_header`. Its examples send no key (nil) unless they
# set `let(:"Idempotency-Key")`.
module SwaggerOffline
  IDEMPOTENCY_KEY_DOC = "OFFLINE §10.1 — 8 to 64 letters, digits, - or _. A retry with the same key replays the " \
                        "first answer (same status and body, header `Idempotent-Replayed: true`; one write). The same " \
                        "key with another body → 422 `idempotency_key_reused`; while the first request still runs → " \
                        "409 `idempotency_in_progress` (retry later); a malformed key → 422 `idempotency_key_invalid`. " \
                        "Without the header (1.1.x apps) nothing changes.".freeze

  def idempotency_key_header
    parameter name: :"Idempotency-Key", in: :header, type: :string, required: false, description: IDEMPOTENCY_KEY_DOC
    let(:"Idempotency-Key") { nil }
  end
end

RSpec.configure { |config| config.extend SwaggerOffline, type: :request }

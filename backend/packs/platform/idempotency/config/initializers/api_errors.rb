# Idempotency domain errors that the API translates to problem+json (see Api::ErrorRegistry).
#
# - KeyReused: 409, same key with another method, path or body. Does not expose the stored body.
# - RequestInProgress: 409, the first request with that key is still running (bounded wait).
# - KeyRequired / KeyInvalid: 400.
# - MissingContext is NOT registered on purpose: it is a programming bug (generic 500, detail only in the log).
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Idempotency::KeyReused, status: :conflict, code: "idempotency.key_reused")
  Api::ErrorRegistry.register(Idempotency::RequestInProgress, status: :conflict, code: "idempotency.request_in_progress")
  Api::ErrorRegistry.register(Idempotency::KeyRequired, status: :bad_request, code: "idempotency.key_required")
  Api::ErrorRegistry.register(Idempotency::KeyInvalid, status: :bad_request, code: "idempotency.key_invalid")
end

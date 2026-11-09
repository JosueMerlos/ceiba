module Idempotency
  # El endpoint exige Idempotency-Key y la petición no la trae. La API responde 400 idempotency.key_required.
  class KeyRequired < Error; end
end

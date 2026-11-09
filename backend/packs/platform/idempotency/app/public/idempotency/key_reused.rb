module Idempotency
  # La Idempotency-Key ya se usó con otra petición (otro método, ruta o cuerpo). La API responde 409 idempotency.key_reused.
  class KeyReused < Error; end
end

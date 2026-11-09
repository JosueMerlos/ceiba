module Idempotency
  # Idempotency-Key vacía, de más de 255 caracteres o con caracteres que no son ASCII imprimible. La API responde 400 idempotency.key_invalid.
  class KeyInvalid < Error; end
end

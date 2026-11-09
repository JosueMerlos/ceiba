module Api
  # Cuerpo de una mutación que no es application/json. Responde 415 (ver ApiRequestGuard).
  class UnsupportedMediaType < StandardError; end
end

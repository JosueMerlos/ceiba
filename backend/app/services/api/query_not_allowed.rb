module Api
  # Mutación con parámetros en la query string (ver ApiRequestGuard). Responde 400.
  class QueryNotAllowed < StandardError; end
end

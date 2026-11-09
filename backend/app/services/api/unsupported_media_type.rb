module Api
  # Cuerpo de una mutación que no es application/json. Responde 415 (ver Api::JsonBody).
  class UnsupportedMediaType < StandardError; end
end

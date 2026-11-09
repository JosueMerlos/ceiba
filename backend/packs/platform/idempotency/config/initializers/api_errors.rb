# Errores de dominio de idempotency que la API traduce a problem+json (ver Api::ErrorRegistry).
#
# - KeyReused: 409, misma clave con otro método, ruta o cuerpo. No expone el cuerpo guardado.
# - KeyRequired / KeyInvalid: 400.
# - MissingContext NO se registra a propósito: es un bug de programación (500 genérico, detalle solo en el log).
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Idempotency::KeyReused, status: :conflict, code: "idempotency.key_reused")
  Api::ErrorRegistry.register(Idempotency::KeyRequired, status: :bad_request, code: "idempotency.key_required")
  Api::ErrorRegistry.register(Idempotency::KeyInvalid, status: :bad_request, code: "idempotency.key_invalid")
end

# OpenAPI schemas of the identity pack (loaded by spec/swagger_helper.rb).
OpenapiComponents.register(
  User: {
    type: :object,
    description: "Persona autenticada. Global: no pertenece a una organización (ADR-0028)",
    properties: {
      id: { type: :string, format: :uuid },
      email: { type: :string, format: :email, description: "Normalizado: minúsculas y sin espacios" },
      full_name: { type: :string }
    },
    required: %i[id email full_name],
    additionalProperties: false
  },
  AuthSession: {
    type: :object,
    description: "Sesión del panel: quién es y el token CSRF que debe enviar en `X-CSRF-Token` en toda mutación",
    properties: {
      user: { "$ref" => "#/components/schemas/User" },
      csrf_token: { type: :string, description: "Ligado a esta sesión; cambia cuando la sesión rota (login). Se guarda en memoria, no en almacenamiento persistente" },
      expires_at: { type: :string, format: "date-time", description: "Caducidad ABSOLUTA de la sesión (UTC); la inactividad de 12 h es aparte" }
    },
    required: %i[user csrf_token expires_at],
    additionalProperties: false
  }
)

require "rails_helper"

# rswag configuration. The rswag specs (spec/api and packs/*/*/spec/api) do two things:
#   1. validate every REAL response against the declared schema. Schemas carry `required` and
#      `additionalProperties: false` by hand (not `openapi_strict_schema_validation`, which makes optional fields such as
#      `detail` mandatory): an extra or missing serializer field breaks the spec;
#   2. generate backend/openapi/v1.yaml (`bin/rails openapi:generate`), which is versioned and feeds the TS client.
#
# Shared components (Problem, ValidationProblem...) are defined here; each pack contributes its own in
# packs/<layer>/<pack>/spec/openapi_components.rb (a name => schema Hash).
module OpenapiComponents
  PROBLEM_FIELDS = {
    type: { type: :string, description: "URN estable del tipo de problema", example: "urn:ceiba:error:resource.not_found" },
    title: { type: :string, description: "Resumen legible, en el idioma de la API", example: "No se encontró el recurso" },
    status: { type: :integer, description: "Código HTTP, repetido en el cuerpo", example: 404 },
    code: { type: :string, description: "Código estable y traducible por el frontend (i18n)", example: "resource.not_found" },
    detail: { type: :string, description: "Explicación específica, solo cuando el error la define" },
    instance: { type: :string, description: "Ruta de la petición", example: "/api/v1/organizations/0198f0a0-0000-7000-8000-000000000000" },
    request_id: { type: :string, description: "Mismo valor que la cabecera X-Request-Id; sirve para buscar el detalle en el log" }
  }.freeze

  def self.all
    {
      Problem: {
        type: :object, description: "application/problem+json (RFC 9457)",
        properties: PROBLEM_FIELDS, required: %i[type title status code instance request_id], additionalProperties: false
      },
      FieldError: {
        type: :object,
        properties: {
          field: { type: :string, example: "company.slug" },
          code: { type: :string, description: "Tipo del error (blank, taken, invalid...)", example: "blank" },
          message: { type: :string, example: "no puede estar en blanco" }
        },
        required: %i[field code message], additionalProperties: false
      },
      ValidationProblem: {
        type: :object, description: "Problema con errores por campo (422 y algunos 400)",
        properties: PROBLEM_FIELDS.merge(errors: { type: :array, items: { "$ref" => "#/components/schemas/FieldError" } }),
        required: %i[type title status code instance request_id errors], additionalProperties: false
      },
      PageInfo: {
        type: :object, description: "Metadatos de la paginación por cursor",
        properties: {
          next_cursor: { type: :string, nullable: true, description: "Cursor opaco para pedir la siguiente página (?after=); null en la última" },
          has_more: { type: :boolean }
        },
        required: %i[next_cursor has_more], additionalProperties: false
      }
    }.merge(pack_components)
  end

  # Idempotency-Key header and its errors, so every idempotent create endpoint references them with $ref. The pattern and
  # length are those of Idempotency::Processor::VALID_KEY.
  IDEMPOTENCY_KEY_PARAMETER = {
    name: "Idempotency-Key", in: :header, required: false,
    description: "Clave única (p. ej. un UUID) que hace seguro reintentar la creación: misma clave y mismo cuerpo repiten la respuesta " \
                 "(cabecera `Idempotency-Replayed: true`) y no crean otro recurso; la misma clave con otro método, ruta o cuerpo da " \
                 "`409 idempotency.key_reused`. Vale 24 horas, por organización y principal.",
    schema: { type: :string, minLength: 1, maxLength: 255, pattern: "^[!-~]+$", example: "0198f0a0-7c3e-7000-8000-5b1f0c2d9e11" }
  }.freeze

  def self.parameters
    {
      IdempotencyKey: IDEMPOTENCY_KEY_PARAMETER,
      IdempotencyKeyRequired: IDEMPOTENCY_KEY_PARAMETER.merge(required: true)
    }
  end

  def self.headers
    {
      IdempotencyReplayed: {
        description: "`true` cuando la respuesta es la guardada de una petición anterior con la misma `Idempotency-Key` (repetida, no ejecutada de nuevo).",
        schema: { type: :string, enum: %w[true] }
      }
    }
  end

  def self.responses
    problem = { "application/problem+json": { schema: { "$ref" => "#/components/schemas/Problem" } } }
    {
      IdempotencyRequestInProgress: {
        description: "Otra petición con la misma `Idempotency-Key` sigue en curso (código `idempotency.request_in_progress`); reintenta con la misma clave",
        content: problem
      },
      IdempotencyKeyReused: { description: "La `Idempotency-Key` ya se usó con otro método, ruta o cuerpo (código `idempotency.key_reused`)", content: problem },
      IdempotencyKeyInvalid: {
        description: "`Idempotency-Key` inválida (`idempotency.key_invalid`) o ausente en un endpoint que la exige (`idempotency.key_required`)", content: problem
      }
    }
  end

  # Each packs/*/*/spec/openapi_components.rb calls OpenapiComponents.register(Name: {...}).
  def self.register(components) = registered.merge!(components)
  def self.registered = (@registered ||= {})

  def self.pack_components
    Rails.root.glob("packs/*/*/spec/openapi_components.rb").sort.each { |file| load file } if registered.empty?
    registered
  end
end

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("openapi").to_s
  config.openapi_format = :yaml

  config.openapi_specs = {
    "v1.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Ceiba API",
        version: "v1",
        description: "Contrato de la API v1. Generado por los specs de rswag; no se edita a mano (docs/architecture/07-api-contract.md)."
      },
      servers: [ { url: "/", description: "Mismo origen (ADR-0013)" } ],
      paths: {},
      components: {
        schemas: OpenapiComponents.all,
        headers: OpenapiComponents.headers,
        parameters: OpenapiComponents.parameters,
        responses: OpenapiComponents.responses,
        securitySchemes: {
          cookieAuth: {
            type: :apiKey, in: :cookie, name: "ceiba_session",
            description: "Cookie de sesión (HttpOnly) que entrega POST /auth/login. En producción se llama `__Host-ceiba_session`. " \
                         "Las mutaciones exigen además `X-CSRF-Token` (el de `csrf_token`) y, si el navegador envía `Origin`, que sea el propio."
          }
        }
      }
    }
  }
end

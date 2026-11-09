require "rails_helper"

# Configuración de rswag (M0.06, ADR-0012). Los specs de rswag (spec/api y packs/*/*/spec/api) hacen dos cosas:
#   1. validan cada respuesta REAL contra el esquema declarado. Los esquemas llevan `required` y `additionalProperties: false`
#      a mano (no `openapi_strict_schema_validation`, que vuelve obligatorios los campos opcionales como `detail`): un campo
#      de más o de menos en el serializer rompe el spec;
#   2. generan backend/openapi/v1.yaml (`bin/rails openapi:generate`), que se versiona y del que sale el cliente TS.
#
# Los componentes compartidos (Problem, ValidationProblem...) se definen aquí; cada pack aporta los suyos en
# packs/<capa>/<pack>/spec/openapi_components.rb (un Hash nombre => esquema).
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

  # Cada packs/*/*/spec/openapi_components.rb llama a OpenapiComponents.register(Nombre: {...}).
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
      components: { schemas: OpenapiComponents.all }
    }
  }
end

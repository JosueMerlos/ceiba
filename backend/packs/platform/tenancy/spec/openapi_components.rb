# Esquemas OpenAPI del pack tenancy (los carga spec/swagger_helper.rb).
OpenapiComponents.register(
  Organization: {
    type: :object,
    description: "Organización: el tenant (ADR-0003)",
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      legal_name: { type: :string, nullable: true },
      country_code: { type: :string, description: "ISO 3166-1 alfa-2", example: "NI" },
      status: { type: :string, enum: %w[active suspended] },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id name legal_name country_code status created_at updated_at],
    additionalProperties: false
  }
)

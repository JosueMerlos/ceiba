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
  },
  Company: {
    type: :object,
    description: "Empresa: un negocio dentro de una organización (ADR-0004)",
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      slug: { type: :string, description: "Único en toda la plataforma (URL pública /c/:slug)", example: "barberia-guegu" },
      business_type: { type: :string, example: "barbershop" },
      currency: { type: :string, enum: %w[NIO USD] },
      locale: { type: :string, example: "es-NI" },
      status: { type: :string, enum: %w[active inactive] },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id name slug business_type currency locale status created_at updated_at],
    additionalProperties: false
  },
  Branch: {
    type: :object,
    description: "Sucursal: una ubicación de una empresa",
    properties: {
      id: { type: :string, format: :uuid },
      company_id: { type: :string, format: :uuid },
      name: { type: :string },
      time_zone: { type: :string, description: "Zona horaria IANA", example: "America/Managua" },
      address: { type: :string, nullable: true },
      phone_e164: { type: :string, nullable: true, example: "+50588887777" },
      status: { type: :string, enum: %w[active inactive] },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id company_id name time_zone address phone_e164 status created_at updated_at],
    additionalProperties: false
  }
)

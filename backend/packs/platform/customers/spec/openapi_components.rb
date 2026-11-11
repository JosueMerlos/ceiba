# OpenAPI schemas of the customers pack.
OpenapiComponents.register(
  Customer: {
    type: :object,
    description: "Cliente de una empresa. El teléfono, el correo y las notas solo salen por los endpoints de clientes (`platform.customer.read`).",
    properties: {
      id: { type: :string, format: :uuid },
      full_name: { type: :string },
      phone_e164: { type: :string, description: "Teléfono en E.164, único por empresa", example: "+50588887777" },
      email: { type: :string, nullable: true },
      notes: { type: :string, nullable: true },
      archived_at: { type: :string, format: "date-time", nullable: true, description: "UTC; null si está activo" },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id full_name phone_e164 email notes archived_at created_at updated_at],
    additionalProperties: false
  },
  CustomerInput: {
    type: :object,
    description: "Alta de un cliente",
    properties: {
      full_name: { type: :string, maxLength: 200 },
      phone_e164: { type: :string, description: "En cualquier formato; se normaliza a E.164 con el país de la organización", example: "8888-7777" },
      email: { type: :string, nullable: true, maxLength: 254 },
      notes: { type: :string, nullable: true, maxLength: 2000 }
    },
    required: %i[full_name phone_e164],
    additionalProperties: false
  },
  CustomerPatch: {
    type: :object,
    description: "Edición parcial de un cliente: solo cambian los campos enviados",
    properties: {
      full_name: { type: :string, maxLength: 200 },
      phone_e164: { type: :string, description: "En cualquier formato; se normaliza a E.164", example: "8888-7777" },
      email: { type: :string, nullable: true, maxLength: 254 },
      notes: { type: :string, nullable: true, maxLength: 2000 }
    },
    additionalProperties: false
  }
)

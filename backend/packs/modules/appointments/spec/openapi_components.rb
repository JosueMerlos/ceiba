# OpenAPI schemas of the appointments pack.
OpenapiComponents.register(
  Service: {
    type: :object,
    description: "Servicio del catálogo de una empresa. El precio es un entero en unidades menores (`price_minor`) en la moneda de la empresa.",
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      duration_minutes: { type: :integer, minimum: 1, maximum: 1440 },
      buffer_before_minutes: { type: :integer, minimum: 0, maximum: 1440 },
      buffer_after_minutes: { type: :integer, minimum: 0, maximum: 1440 },
      price_minor: { type: :integer, format: :int64, minimum: 0, maximum: 9_007_199_254_740_991, description: "Precio en unidades menores (centavos)", example: 20_000 },
      currency: { type: :string, enum: %w[NIO USD], description: "Siempre la moneda de la empresa" },
      active: { type: :boolean },
      position: { type: :integer, minimum: 0, description: "Orden en el catálogo (menor primero)" },
      archived_at: { type: :string, format: "date-time", nullable: true, description: "UTC; null si no está archivado" },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id name duration_minutes buffer_before_minutes buffer_after_minutes price_minor currency active position archived_at created_at updated_at],
    additionalProperties: false
  },
  ServiceInput: {
    type: :object,
    description: "Alta de un servicio. Sin `currency` toma la de la empresa; si se envía debe ser la de la empresa (si no, 422).",
    properties: {
      name: { type: :string, maxLength: 200 },
      duration_minutes: { type: :integer, minimum: 1, maximum: 1440 },
      buffer_before_minutes: { type: :integer, minimum: 0, maximum: 1440, default: 0 },
      buffer_after_minutes: { type: :integer, minimum: 0, maximum: 1440, default: 0 },
      price_minor: { type: :integer, format: :int64, minimum: 0, maximum: 9_007_199_254_740_991, example: 20_000 },
      currency: { type: :string, enum: %w[NIO USD] },
      active: { type: :boolean, default: true },
      position: { type: :integer, minimum: 0, default: 0 }
    },
    required: %i[name duration_minutes price_minor],
    additionalProperties: false
  },
  ServicePatch: {
    type: :object,
    description: "Edición parcial de un servicio: solo cambian los campos enviados",
    properties: {
      name: { type: :string, maxLength: 200 },
      duration_minutes: { type: :integer, minimum: 1, maximum: 1440 },
      buffer_before_minutes: { type: :integer, minimum: 0, maximum: 1440 },
      buffer_after_minutes: { type: :integer, minimum: 0, maximum: 1440 },
      price_minor: { type: :integer, format: :int64, minimum: 0, maximum: 9_007_199_254_740_991 },
      currency: { type: :string, enum: %w[NIO USD] },
      active: { type: :boolean },
      position: { type: :integer, minimum: 0 }
    },
    additionalProperties: false
  },
  ServiceOverride: {
    type: :object,
    description: "Duración y/o precio propios de una sucursal para un servicio. Un valor null significa que la sucursal usa el del servicio.",
    properties: {
      id: { type: :string, format: :uuid },
      branch_id: { type: :string, format: :uuid },
      service_id: { type: :string, format: :uuid },
      duration_minutes: { type: :integer, nullable: true, minimum: 1, maximum: 1440 },
      price_minor: { type: :integer, format: :int64, nullable: true, minimum: 0 },
      currency: { type: :string, enum: %w[NIO USD], description: "La del servicio: el override no tiene moneda propia" },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id branch_id service_id duration_minutes price_minor currency created_at updated_at],
    additionalProperties: false
  },
  ServiceOverrideInput: {
    type: :object,
    description: "Cambio de un override. Cambia SOLO los campos enviados; lo que no viene se conserva. Un `null` explícito quita ese valor. " \
                 "El resultado debe tener al menos uno de los dos (para quitarlo todo, `DELETE`).",
    properties: {
      duration_minutes: { type: :integer, nullable: true, minimum: 1, maximum: 1440 },
      price_minor: { type: :integer, format: :int64, nullable: true, minimum: 0 }
    },
    additionalProperties: false
  }
)

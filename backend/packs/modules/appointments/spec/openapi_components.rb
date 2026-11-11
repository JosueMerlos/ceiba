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
  },
  Professional: {
    type: :object,
    description: "Profesional de una empresa. Una misma persona (`user_id`) puede tener un registro en cada empresa del grupo, con su propio horario. " \
                 "No trae datos de la persona vinculada: solo su identificador.",
    properties: {
      id: { type: :string, format: :uuid },
      display_name: { type: :string, maxLength: 120 },
      user_id: { type: :string, format: :uuid, nullable: true, description: "Persona vinculada; null si el profesional no tiene usuario" },
      active: { type: :boolean },
      archived_at: { type: :string, format: "date-time", nullable: true, description: "UTC; null si no está archivado" },
      branch_ids: { type: :array, items: { type: :string, format: :uuid }, description: "Sucursales de la empresa donde está asignado" },
      service_ids: { type: :array, items: { type: :string, format: :uuid }, description: "Servicios que presta" },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id display_name user_id active archived_at branch_ids service_ids created_at updated_at],
    additionalProperties: false
  },
  ProfessionalInput: {
    type: :object,
    description: "Alta de un profesional. `user_id` debe tener una membresía en la organización y no estar ya vinculado a otro profesional de la empresa.",
    properties: {
      display_name: { type: :string, minLength: 1, maxLength: 120 },
      user_id: { type: :string, format: :uuid, nullable: true },
      active: { type: :boolean, default: true }
    },
    required: %i[display_name],
    additionalProperties: false
  },
  ProfessionalPatch: {
    type: :object,
    description: "Edición parcial de un profesional: solo cambian los campos enviados; `user_id: null` desvincula a la persona",
    properties: {
      display_name: { type: :string, minLength: 1, maxLength: 120 },
      user_id: { type: :string, format: :uuid, nullable: true },
      active: { type: :boolean }
    },
    additionalProperties: false
  },
  ProfessionalServicesInput: {
    type: :object,
    description: "El conjunto completo de servicios que presta el profesional; lo que no viene se quita",
    properties: {
      service_ids: { type: :array, items: { type: :string, format: :uuid }, uniqueItems: true }
    },
    required: %i[service_ids],
    additionalProperties: false
  }
)

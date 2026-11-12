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
  },
  Resource: {
    type: :object,
    description: "Recurso físico de una sucursal (sillón, sala, equipo).",
    properties: {
      id: { type: :string, format: :uuid },
      branch_id: { type: :string, format: :uuid },
      name: { type: :string, maxLength: 120 },
      kind: { type: :string, enum: %w[chair room equipment] },
      active: { type: :boolean },
      archived_at: { type: :string, format: "date-time", nullable: true, description: "UTC; null si no está archivado" },
      created_at: { type: :string, format: "date-time", description: "UTC" },
      updated_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id branch_id name kind active archived_at created_at updated_at],
    additionalProperties: false
  },
  ResourceInput: {
    type: :object,
    description: "Alta de un recurso en la sucursal de la ruta.",
    properties: {
      name: { type: :string, minLength: 1, maxLength: 120 },
      kind: { type: :string, enum: %w[chair room equipment] },
      active: { type: :boolean, default: true }
    },
    required: %i[name kind],
    additionalProperties: false
  },
  ResourcePatch: {
    type: :object,
    description: "Edición parcial de un recurso: solo cambian los campos enviados",
    properties: {
      name: { type: :string, minLength: 1, maxLength: 120 },
      kind: { type: :string, enum: %w[chair room equipment] },
      active: { type: :boolean }
    },
    additionalProperties: false
  },
  ServiceResourceRequirements: {
    type: :object,
    description: "Los tipos de recurso que necesita un servicio: el hueco de agenda exige un recurso compatible de cada tipo en la sucursal.",
    properties: {
      service_id: { type: :string, format: :uuid },
      kinds: { type: :array, items: { type: :string, enum: %w[chair room equipment] }, uniqueItems: true }
    },
    required: %i[service_id kinds],
    additionalProperties: false
  },
  ServiceResourceRequirementsInput: {
    type: :object,
    description: "El conjunto completo de tipos de recurso que necesita el servicio; lo que no viene se quita",
    properties: {
      kinds: { type: :array, items: { type: :string, enum: %w[chair room equipment] }, uniqueItems: true }
    },
    required: %i[kinds],
    additionalProperties: false
  },
  WeeklyScheduleSlot: {
    type: :object,
    description: "Una franja semanal en hora LOCAL de la sucursal (sin zona; la zona es de la sucursal).",
    properties: {
      id: { type: :string, format: :uuid },
      weekday: { type: :integer, minimum: 0, maximum: 6, description: "0 = domingo, como `Date#wday`" },
      starts_at_local: { type: :string, pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", example: "09:00" },
      ends_at_local: { type: :string, pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", example: "13:00" }
    },
    required: %i[id weekday starts_at_local ends_at_local],
    additionalProperties: false
  },
  WeeklyScheduleInput: {
    type: :object,
    description: "El horario completo del dueño en la sucursal: reemplaza todas sus franjas. Horas `HH:MM` (minutos enteros), inicio antes que fin, sin cruzar la medianoche.",
    properties: {
      slots: {
        type: :array, maxItems: 100,
        items: {
          type: :object,
          properties: {
            weekday: { type: :integer, minimum: 0, maximum: 6 },
            starts_at_local: { type: :string, example: "09:00" },
            ends_at_local: { type: :string, example: "13:00" }
          },
          required: %i[weekday starts_at_local ends_at_local],
          additionalProperties: false
        }
      }
    },
    required: %i[slots],
    additionalProperties: false
  },
  TimeOff: {
    type: :object,
    description: "Ausencia de un profesional o de un recurso (exactamente uno de `professional_id` y `resource_id`).",
    properties: {
      id: { type: :string, format: :uuid },
      professional_id: { type: :string, format: :uuid, nullable: true },
      resource_id: { type: :string, format: :uuid, nullable: true },
      starts_at: { type: :string, format: "date-time", description: "UTC" },
      ends_at: { type: :string, format: "date-time", description: "UTC" },
      reason: { type: :string, maxLength: 200, nullable: true, description: "Texto libre opcional; sin datos de salud" },
      created_at: { type: :string, format: "date-time", description: "UTC" }
    },
    required: %i[id professional_id resource_id starts_at ends_at reason created_at],
    additionalProperties: false
  },
  TimeOffInput: {
    type: :object,
    description: "Alta de una ausencia: `starts_at` antes que `ends_at`, hasta 366 días. El dueño es el de la ruta.",
    properties: {
      starts_at: { type: :string, format: "date-time" },
      ends_at: { type: :string, format: "date-time" },
      reason: { type: :string, maxLength: 200, nullable: true, description: "Texto libre opcional; sin datos de salud. No se registra en logs ni en la auditoría" }
    },
    required: %i[starts_at ends_at],
    additionalProperties: false
  },
  AvailabilitySlot: {
    type: :object,
    description: "Un inicio posible para los servicios y su fin (inicio + duración efectiva total). Instantes UTC. `professional_id` es quien atiende " \
                  "(el asignado si se pidió `any`) y `resource_id` el recurso reservado, o nulo si los servicios no piden recurso.",
    properties: {
      starts_at: { type: :string, format: "date-time", description: "UTC" },
      ends_at: { type: :string, format: "date-time", description: "UTC" },
      professional_id: { type: :string, format: :uuid },
      resource_id: { type: :string, format: :uuid, nullable: true }
    },
    required: %i[starts_at ends_at professional_id resource_id],
    additionalProperties: false
  },
  AvailabilityPrice: {
    type: :object,
    description: "Precio total de los servicios pedidos en la sucursal (con sus overrides): entero en unidades menores y moneda.",
    properties: {
      amount_minor: { type: :integer, format: :int64, minimum: 0, example: 25_000 },
      currency: { type: :string, example: "NIO" }
    },
    required: %i[amount_minor currency],
    additionalProperties: false
  }
)

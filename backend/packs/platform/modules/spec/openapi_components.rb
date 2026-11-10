# Esquemas OpenAPI del pack modules (los carga spec/swagger_helper.rb).
OpenapiComponents.register(
  ModuleActivation: {
    type: :object,
    properties: {
      data: {
        type: :object,
        properties: { key: { type: :string }, enabled: { type: :boolean }, changed: { type: :boolean, description: "false si la llamada fue una repetición" } },
        required: %i[key enabled changed], additionalProperties: false
      }
    },
    required: %i[data], additionalProperties: false
  },
  ModuleSettings: {
    type: :object,
    properties: {
      data: {
        type: :object,
        properties: { key: { type: :string }, settings: { type: :object, additionalProperties: true, description: "Settings resueltos del nivel escrito (default -> empresa -> sucursal)" } },
        required: %i[key settings], additionalProperties: false
      }
    },
    required: %i[data], additionalProperties: false
  },
  Me: {
    type: :object,
    description: "Respuesta de GET /api/v1/me",
    properties: {
      data: {
        type: :object,
        properties: {
          principal: {
            type: :object,
            properties: { id: { type: :string, format: :uuid }, name: { type: :string }, email: { type: :string } },
            required: %i[id name email], additionalProperties: false
          },
          context: {
            type: :object,
            description: "Lo elegido; cada nivel es null si no hay (usuario sin memberships, sin sucursal elegida)",
            properties: {
              organization: { allOf: [ { "$ref" => "#/components/schemas/OrganizationSummary" } ], nullable: true },
              company: { allOf: [ { "$ref" => "#/components/schemas/Company" } ], nullable: true },
              branch: { allOf: [ { "$ref" => "#/components/schemas/Branch" } ], nullable: true }
            },
            required: %i[organization company branch], additionalProperties: false
          },
          modules: {
            type: :array,
            description: "Módulos ACTIVOS en la empresa del contexto, con los settings resueltos (default -> empresa -> sucursal)",
            items: {
              type: :object,
              properties: {
                key: { type: :string, example: "appointments" },
                version: { type: :string, example: "1.0" },
                settings: { type: :object, additionalProperties: true }
              },
              required: %i[key version settings], additionalProperties: false
            }
          },
          permissions: {
            type: :array, items: { type: :string },
            description: "Permisos que el usuario ejerce en el contexto, de los módulos activos y de la plataforma. El frontend los refleja; no decide."
          },
          navigation: {
            type: :array,
            items: {
              type: :object,
              properties: { module: { type: :string }, key: { type: :string }, path: { type: :string, example: "/agenda" } },
              required: %i[module key path], additionalProperties: false
            }
          }
        },
        required: %i[principal context modules permissions navigation], additionalProperties: false
      }
    },
    required: %i[data], additionalProperties: false
  }
)

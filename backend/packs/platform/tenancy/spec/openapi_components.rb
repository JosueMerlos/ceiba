# OpenAPI schemas of the tenancy pack.
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
  OrganizationSummary: {
    type: :object,
    description: "Resumen de una organización para el selector de contexto (id, nombre, estado)",
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      status: { type: :string, enum: %w[active suspended] }
    },
    required: %i[id name status],
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
  },
  LogoAsset: {
    type: :object, nullable: true,
    description: "Variantes del logo: x1 (alto 64) y x2 (alto 128), WebP. Cada URL es versionada: una imagen nueva tiene URLs nuevas. Nunca apuntan al original. Es null si no hay imagen.",
    properties: { x1: { type: :string, description: "Ruta relativa bajo /api/storage" }, x2: { type: :string, description: "Ruta relativa bajo /api/storage" } },
    required: %i[x1 x2], additionalProperties: false,
    example: { x1: "/api/storage/representations/proxy/<signed_blob_id>/<variation_key>/logo.webp" }
  },
  BannerAsset: {
    type: :object, nullable: true,
    description: "Variantes del banner: wide (16:9) y standard (4:3), WebP. Cada URL es versionada: una imagen nueva tiene URLs nuevas. Nunca apuntan al original. Es null si no hay imagen.",
    properties: { wide: { type: :string, description: "Ruta relativa bajo /api/storage" }, standard: { type: :string, description: "Ruta relativa bajo /api/storage" } },
    required: %i[wide standard], additionalProperties: false,
    example: { wide: "/api/storage/representations/proxy/<signed_blob_id>/<variation_key>/banner.webp" }
  },
  FaviconAsset: {
    type: :object, nullable: true,
    description: "Variantes del favicon: icon32 e icon180, PNG. Cada URL es versionada: una imagen nueva tiene URLs nuevas. Nunca apuntan al original. Es null si no hay imagen.",
    properties: { icon32: { type: :string, description: "Ruta relativa bajo /api/storage" }, icon180: { type: :string, description: "Ruta relativa bajo /api/storage" } },
    required: %i[icon32 icon180], additionalProperties: false,
    example: { icon32: "/api/storage/representations/proxy/<signed_blob_id>/<variation_key>/favicon.png" }
  },
  Branding: {
    type: :object,
    description: "Marca de una empresa. Todo valor es null mientras no se personalice: aplica la paleta de la plataforma.",
    properties: {
      brand_name: { type: :string, nullable: true, maxLength: 80 },
      tagline: { type: :string, nullable: true, maxLength: 140 },
      primary_color: { type: :string, nullable: true, pattern: "^#[0-9A-F]{6}$", example: "#1D6C4E" },
      secondary_color: { type: :string, nullable: true, pattern: "^#[0-9A-F]{6}$" },
      accent_color: { type: :string, nullable: true, pattern: "^#[0-9A-F]{6}$" },
      font_choice: { type: :string, nullable: true, enum: %w[figtree lora nunito] },
      assets: {
        type: :object,
        properties: {
          logo: { "$ref" => "#/components/schemas/LogoAsset" },
          banner: { "$ref" => "#/components/schemas/BannerAsset" },
          favicon: { "$ref" => "#/components/schemas/FaviconAsset" }
        },
        required: %i[logo banner favicon], additionalProperties: false
      }
    },
    required: %i[brand_name tagline primary_color secondary_color accent_color font_choice assets],
    additionalProperties: false
  },
  BrandingUpdate: {
    type: :object,
    description: "Cuerpo multipart/form-data de PATCH de la marca. Solo cambia lo enviado; un campo vacío vuelve al default; `remove[]` quita archivos.",
    properties: {
      brand_name: { type: :string, maxLength: 80 },
      tagline: { type: :string, maxLength: 140 },
      primary_color: { type: :string, description: "#RRGGBB (se normaliza a mayúsculas)", example: "#FFFF00" },
      secondary_color: { type: :string },
      accent_color: { type: :string },
      font_choice: { type: :string, enum: %w[figtree lora nunito] },
      logo: { type: :string, format: :binary, description: "PNG, JPEG o WebP de hasta 2 MB y 4096 px por lado" },
      banner: { type: :string, format: :binary, description: "PNG, JPEG o WebP de hasta 5 MB y 4096 px por lado" },
      favicon: { type: :string, format: :binary, description: "PNG, JPEG o WebP de hasta 200 KB y 4096 px por lado" },
      remove: { type: :array, items: { type: :string, enum: %w[logo banner favicon] } }
    },
    additionalProperties: false
  }
)

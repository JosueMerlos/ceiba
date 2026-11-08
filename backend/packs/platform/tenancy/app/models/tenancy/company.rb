module Tenancy
  # Empresa: giro, moneda, catálogo y marca de un negocio dentro de una organización. Tabla tenant (acts_as_tenant)
  # pero NO es el tenant: es un alcance de autorización (ADR-0003, ADR-0004).
  class Company < ApplicationRecord
    # Segmentos de la URL pública /c/:slug que no pueden ser el slug de un negocio.
    RESERVED_SLUGS = %w[
      api admin app c www help docs blog status support soporte login logout signup register registro auth
      assets static public cdn mail smtp ftp health ready billing panel booking reservar reservas
      ceiba webhooks webhook staging dev test root null undefined
    ].freeze
    SLUG_FORMAT = /\A[a-z0-9-]{3,40}\z/
    CURRENCIES = %w[NIO USD].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    enum :status, { active: "active", inactive: "inactive" }, default: "active", validate: true

    has_many :branches, class_name: "Tenancy::Branch", inverse_of: :company

    normalizes :slug, with: ->(slug) { slug.strip.downcase }

    validates :name, :business_type, presence: true
    validates :slug, presence: true, format: { with: SLUG_FORMAT }, exclusion: { in: RESERVED_SLUGS },
                     uniqueness: true
    validates :currency, inclusion: { in: CURRENCIES }
    validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
  end
end

# companies es tabla tenant: organization_id, FK a organizations, UNIQUE (organization_id, id) para las FKs
# compuestas de sus hijas y la política RLS (deshabilitada hasta M4.03) las pone create_tenant_table.
#
# on_delete: restrict (el default). Borrar una organización con empresas es un offboarding explícito (exportar,
# retener, borrar por organization_id: P3), nunca un efecto lateral de un DELETE; con cascade, un destroy
# accidental de la organización borraría en silencio todo su negocio.
class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :business_type, null: false
      t.string :currency, limit: 3, null: false
      t.string :locale, null: false, default: "es-NI"
      t.string :status, null: false, default: "active"
      t.timestamps

      # La URL pública es /c/:slug: único en TODA la plataforma, no por organización.
      t.index :slug, unique: true, name: "uq_companies_slug"
      t.check_constraint "slug ~ '^[a-z0-9-]{3,40}$'", name: "chk_companies_slug_format"
      t.check_constraint "currency IN ('NIO', 'USD')", name: "chk_companies_currency"
      t.check_constraint "status IN ('active', 'inactive')", name: "chk_companies_status"
    end
  end
end

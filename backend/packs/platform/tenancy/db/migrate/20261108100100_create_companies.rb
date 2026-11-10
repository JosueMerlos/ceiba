# companies is a tenant table: create_tenant_table adds organization_id, the FK to organizations, UNIQUE (organization_id, id)
# for its children's composite FKs and the RLS policy (disabled for now).
#
# on_delete: restrict (the default). Deleting an organization with companies is an explicit offboarding (export, retain,
# delete by organization_id), never a side effect of a DELETE; with cascade, an accidental destroy of the organization would
# silently wipe its whole business.
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

      # The public URL is /c/:slug: unique across the WHOLE platform, not per organization.
      t.index :slug, unique: true, name: "uq_companies_slug"
      t.check_constraint "slug ~ '^[a-z0-9-]{3,40}$'", name: "chk_companies_slug_format"
      t.check_constraint "currency = 'NIO' OR currency = 'USD'", name: "chk_companies_currency"
      t.check_constraint "status = 'active' OR status = 'inactive'", name: "chk_companies_status"
    end
  end
end

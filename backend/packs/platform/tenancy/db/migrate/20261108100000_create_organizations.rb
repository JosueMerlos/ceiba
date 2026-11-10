# organizations is the tenant ROOT: it has no organization_id, hence create_table instead of create_tenant_table. Every other
# tenant table hangs from it.
# CHECKs use OR instead of IN (...): PostgreSQL dumps `IN` on varchar in two different forms depending on the path (migrating
# from scratch vs. rolling back and migrating) and structure.sql would stop being deterministic.
class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :legal_name
      t.string :country_code, limit: 2, null: false, default: "NI"
      t.string :status, null: false, default: "active"
      t.timestamps

      t.check_constraint "status = 'active' OR status = 'suspended'", name: "chk_organizations_status"
      t.check_constraint "country_code ~ '^[A-Z]{2}$'", name: "chk_organizations_country_code"
    end
  end
end

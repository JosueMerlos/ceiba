# organizations es la RAÍZ del tenant (docs/architecture/03-multi-tenancy.md): no lleva organization_id, por eso se
# crea con create_table y no con create_tenant_table. Todas las demás tablas tenant cuelgan de ella.
class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :legal_name
      t.string :country_code, limit: 2, null: false, default: "NI"
      t.string :status, null: false, default: "active"
      t.timestamps

      t.check_constraint "status IN ('active', 'suspended')", name: "chk_organizations_status"
      t.check_constraint "country_code ~ '^[A-Z]{2}$'", name: "chk_organizations_country_code"
    end
  end
end

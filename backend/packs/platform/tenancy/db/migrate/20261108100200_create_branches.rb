# branches: tabla tenant colgada de companies por FK COMPUESTA (organization_id, company_id) -> companies
# (organization_id, id) (t.tenant_reference): la base impide que una sucursal de la organización A cuelgue de una
# empresa de B, aunque el código se salte las validaciones (barrera 2, docs/architecture/03-multi-tenancy.md).
#
# on_delete: restrict (el default) en ambas FKs, igual que companies: una empresa con sucursales no se borra de rebote.
class CreateBranches < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :branches do |t|
      t.tenant_reference :company
      t.string :name, null: false
      t.string :time_zone, null: false, default: "America/Managua"
      t.string :address
      t.string :phone_e164
      t.string :status, null: false, default: "active"
      t.timestamps

      t.check_constraint "status = 'active' OR status = 'inactive'", name: "chk_branches_status"
      t.check_constraint "phone_e164 IS NULL OR phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'", name: "chk_branches_phone_e164"
    end
  end
end

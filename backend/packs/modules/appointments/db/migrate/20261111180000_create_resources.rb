# resources: the physical things of a branch that appointments may need (a chair, a room, a piece of equipment). Tenant
# table; company_id is stored so the composite FK can prove the branch belongs to the SAME company. A resource is archived
# (archived_at), never deleted: bookings will reference it.
#
# Two UNIQUE targets: (organization_id, company_id, id) for the FK of the absences, and (organization_id, company_id,
# branch_id, id) for the FK of the weekly schedules, so the database refuses hours of a resource in a branch that is not its own.
class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :resources do |t|
      t.tenant_reference :company, index: false
      t.uuid :branch_id, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.boolean :active, null: false, default: true
      t.datetime :archived_at
      t.timestamps

      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_resources_branch"

      t.check_constraint "kind = 'chair' OR kind = 'room' OR kind = 'equipment'", name: "chk_resources_kind"
      t.check_constraint "length(btrim(name)) > 0", name: "chk_resources_name_present"

      t.index %i[organization_id company_id id], unique: true, name: "uq_resources_org_company_id"
      t.index %i[organization_id company_id branch_id id], unique: true, name: "uq_resources_org_company_branch_id"
      # The listing of a branch: non-archived resources, paginated by id.
      t.index %i[organization_id branch_id id], where: "archived_at IS NULL", name: "idx_resources_branch_unarchived_id"
    end
  end
end

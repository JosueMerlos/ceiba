# professional_branch_assignments: the branches where a professional attends. Tenant table; company_id is stored so the
# composite FKs can prove the professional and the branch belong to the SAME company (and organization): the database
# refuses an assignment that mixes companies.
#
# UNIQUE (organization_id, company_id, professional_id, branch_id) is the target of the composite FK that weekly schedules
# will use, so a professional can only have hours in a branch where they are assigned.
class CreateProfessionalBranchAssignments < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :professional_branch_assignments do |t|
      t.tenant_reference :company, index: false
      t.uuid :professional_id, null: false
      t.uuid :branch_id, null: false
      t.timestamps

      t.foreign_key :professionals, column: %i[organization_id company_id professional_id], primary_key: %i[organization_id company_id id],
        name: "fk_pba_professional"
      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_pba_branch"

      t.index %i[professional_id branch_id], unique: true, name: "uq_pba_professional_branch"
      t.index %i[organization_id company_id professional_id branch_id], unique: true, name: "uq_pba_org_company_professional_branch"
      # The branch side of the composite FK and "who works in this branch".
      t.index %i[organization_id company_id branch_id], name: "idx_pba_branch"
    end
  end
end

# service_resource_requirements: the KIND of resource a service needs ("this service needs a chair in the branch"), not a
# specific resource: availability looks for any compatible resource of the branch. Tenant table; company_id is stored so the
# composite FK can prove the service belongs to the SAME company.
class CreateServiceResourceRequirements < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :service_resource_requirements do |t|
      t.tenant_reference :company, index: false
      t.uuid :service_id, null: false
      t.string :kind, null: false
      t.timestamps

      t.foreign_key :services, column: %i[organization_id company_id service_id], primary_key: %i[organization_id company_id id],
        name: "fk_srr_service"

      t.check_constraint "kind = 'chair' OR kind = 'room' OR kind = 'equipment'", name: "chk_srr_kind"

      t.index %i[service_id kind], unique: true, name: "uq_srr_service_kind"
      # The service side of the composite FK and "which services need this kind of resource".
      t.index %i[organization_id company_id service_id], name: "idx_srr_service"
    end
  end
end

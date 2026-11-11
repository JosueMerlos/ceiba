# professional_services: the services a professional performs. Tenant table; company_id is stored so the composite FKs can
# prove the professional and the service belong to the SAME company (and organization).
class CreateProfessionalServices < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :professional_services do |t|
      t.tenant_reference :company, index: false
      t.uuid :professional_id, null: false
      t.uuid :service_id, null: false
      t.timestamps

      t.foreign_key :professionals, column: %i[organization_id company_id professional_id], primary_key: %i[organization_id company_id id],
        name: "fk_ps_professional"
      t.foreign_key :services, column: %i[organization_id company_id service_id], primary_key: %i[organization_id company_id id],
        name: "fk_ps_service"

      t.index %i[professional_id service_id], unique: true, name: "uq_ps_professional_service"
      # The service side of the composite FK and "who performs this service".
      t.index %i[organization_id company_id service_id], name: "idx_ps_service"
    end
  end
end

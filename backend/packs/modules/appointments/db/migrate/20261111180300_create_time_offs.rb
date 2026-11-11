# time_offs: absences of a professional or of a resource, as an exact interval in UTC (timestamptz). An absence belongs to the
# person (or the resource) in the company, not to a branch: it blocks them wherever they are assigned. Overlapping absences of
# the same owner are allowed: availability subtracts their union. Tenant table.
#
# The owner is NOT polymorphic (an owner_id could not carry a foreign key): one nullable column per kind plus a CHECK that
# exactly the matching one is set, and composite FKs that prove the owner belongs to the SAME company.
class CreateTimeOffs < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :time_offs do |t|
      t.tenant_reference :company, index: false
      t.string :owner_type, null: false
      t.uuid :professional_id
      t.uuid :resource_id
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      # Free text that may reveal something private: never logged, never audited.
      t.string :reason
      t.timestamps

      # MATCH SIMPLE: each FK is enforced only while its owner column is set.
      t.foreign_key :professionals, column: %i[organization_id company_id professional_id], primary_key: %i[organization_id company_id id],
        name: "fk_time_offs_professional"
      t.foreign_key :resources, column: %i[organization_id company_id resource_id], primary_key: %i[organization_id company_id id],
        name: "fk_time_offs_resource"

      t.check_constraint "(owner_type = 'professional' AND professional_id IS NOT NULL AND resource_id IS NULL) OR " \
                         "(owner_type = 'resource' AND professional_id IS NULL AND resource_id IS NOT NULL)", name: "chk_time_offs_owner"
      t.check_constraint "starts_at < ends_at", name: "chk_time_offs_range"
      t.check_constraint "reason IS NULL OR char_length(reason) <= 200", name: "chk_time_offs_reason"

      # What the engine reads by range, and the listing of an owner.
      t.index %i[professional_id starts_at], where: "professional_id IS NOT NULL", name: "idx_time_offs_professional_starts"
      t.index %i[resource_id starts_at], where: "resource_id IS NOT NULL", name: "idx_time_offs_resource_starts"
    end
  end
end

# appointments: the minimal booked slot the availability engine reads. A professional has ONE agenda across all their branches,
# so the engine subtracts the appointments of the person wherever they are. `blocks_from`/`blocks_to` is what the slot occupies
# (equal to starts_at/ends_at until buffers exist). Tenant table.
#
# No agenda constraints yet: the engine suggests, a later migration makes the database decide.
class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :appointments do |t|
      t.tenant_reference :company, index: false
      t.uuid :branch_id, null: false
      t.uuid :professional_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :blocks_from, null: false
      t.datetime :blocks_to, null: false
      t.string :status, null: false, default: "scheduled"
      t.timestamps

      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointments_branch"
      t.foreign_key :professionals, column: %i[organization_id company_id professional_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointments_professional"

      # No (organization_id, company_id) index of its own: the two FK-side indexes below start with that pair.
      # The sides of the composite FKs (deleting a branch or a professional looks here).
      t.index %i[organization_id company_id branch_id], name: "idx_appointments_branch"
      t.index %i[organization_id company_id professional_id], name: "idx_appointments_professional"
      # The agendas: one branch's day and one professional's day.
      t.index %i[organization_id branch_id starts_at], name: "idx_appointments_branch_starts"
      t.index %i[organization_id professional_id starts_at], name: "idx_appointments_professional_starts"
      # What the engine reads: the blocking slots of a professional by range, in every branch.
      t.index %i[organization_id professional_id blocks_from], name: "idx_appointments_professional_blocks"
    end
  end
end

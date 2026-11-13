# appointments, recreated so the database decides the agenda: no two blocking appointments of a professional (or of a resource)
# overlap, the resource belongs to the appointment's branch and the customer to its company.
#
# Recreated instead of altered because strong_migrations rejects adding an EXCLUDE constraint to an existing table (PostgreSQL has
# no NOT VALID nor USING INDEX for it), while the same constraint inside the table's own creation is accepted. No data is ever
# dropped: the migration refuses to run unless the table is empty.
#
# The ranges use tsrange because the columns are `timestamp without time zone` holding UTC; tstzrange would depend on the session.
class RecreateAppointmentsWithAgendaConstraints < ActiveRecord::Migration[8.1]
  RELEASED = "status NOT IN ('cancelled', 'rescheduled')".freeze
  RANGE = "tsrange(blocks_from, blocks_to, '[)')".freeze
  STATUSES = %w[scheduled confirmed checked_in completed cancelled rescheduled no_show].freeze

  def up
    guard_empty!
    drop_table :appointments

    create_tenant_table :appointments do |t|
      add_columns(t)
      t.uuid :customer_id, null: false
      t.string :source, null: false
      # Free text that may reveal something private: stored encrypted, so no length CHECK is possible.
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.string :created_by_type, null: false
      # Who created it, by id only: the actor may be a user, an API key, the system or a public token, so no FK.
      t.uuid :created_by_id
      t.uuid :rescheduled_from_id

      add_foreign_keys(t, resource_key: %i[organization_id branch_id], resource_target: %i[organization_id branch_id id])
      t.foreign_key :customers, column: %i[organization_id company_id customer_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointments_customer"
      t.foreign_key :appointments, column: %i[organization_id company_id rescheduled_from_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointments_rescheduled_from"
      # The target of the child tables' composite FKs and of the self reference above.
      t.unique_constraint %i[organization_id company_id id], name: "uq_appointments_org_company_id"

      t.check_constraint "starts_at < ends_at AND blocks_from <= starts_at AND blocks_to >= ends_at", name: "chk_appointments_valid_interval"
      t.check_constraint "status IN (#{STATUSES.map { |status| "'#{status}'" }.join(', ')})", name: "chk_appointments_status"
      t.check_constraint "source IN ('panel', 'public_booking')", name: "chk_appointments_source"
      t.check_constraint "created_by_type IN ('user', 'api_key', 'system', 'public_token', 'platform_staff')", name: "chk_appointments_created_by_type"

      t.exclusion_constraint "professional_id WITH =, #{RANGE} WITH &&", using: :gist, where: RELEASED, name: "no_overlap_professional"
      t.exclusion_constraint "resource_id WITH =, #{RANGE} WITH &&", using: :gist, where: "resource_id IS NOT NULL AND #{RELEASED}",
        name: "no_overlap_resource"

      add_indexes(t)
      # The resource side of its composite FK (deleting a resource looks here).
      t.index %i[organization_id branch_id resource_id], where: "resource_id IS NOT NULL", name: "idx_appointments_resource"
      t.index %i[organization_id company_id customer_id], name: "idx_appointments_customer"
      t.index %i[organization_id company_id rescheduled_from_id], where: "rescheduled_from_id IS NOT NULL", name: "idx_appointments_rescheduled_from"
    end
  end

  # Back to the minimal shape, with the same guard.
  def down
    guard_empty!
    drop_table :appointments

    create_tenant_table :appointments do |t|
      add_columns(t)
      add_foreign_keys(t, resource_key: %i[organization_id company_id], resource_target: %i[organization_id company_id id])
      add_indexes(t)
      t.index %i[organization_id company_id resource_id], where: "resource_id IS NOT NULL", name: "idx_appointments_resource"
    end
  end

  private

  def guard_empty!
    raise "appointments is not empty; refusing to recreate it" if select_value("SELECT EXISTS (SELECT 1 FROM appointments)")
  end

  def add_columns(t)
    t.tenant_reference :company, index: false
    t.uuid :branch_id, null: false
    t.uuid :professional_id, null: false
    t.uuid :resource_id
    t.datetime :starts_at, null: false
    t.datetime :ends_at, null: false
    t.datetime :blocks_from, null: false
    t.datetime :blocks_to, null: false
    t.string :status, null: false, default: "scheduled"
    t.timestamps
  end

  def add_foreign_keys(t, resource_key:, resource_target:)
    t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
      name: "fk_appointments_branch"
    t.foreign_key :professionals, column: %i[organization_id company_id professional_id], primary_key: %i[organization_id company_id id],
      name: "fk_appointments_professional"
    t.foreign_key :resources, column: [ *resource_key, :resource_id ], primary_key: resource_target, name: "fk_appointments_resource"
  end

  # The indexes shared by both shapes. No (organization_id, company_id) index of its own: the first two start with that pair.
  def add_indexes(t)
    t.index %i[organization_id company_id branch_id], name: "idx_appointments_branch"
    t.index %i[organization_id company_id professional_id], name: "idx_appointments_professional"
    t.index %i[organization_id branch_id starts_at], name: "idx_appointments_branch_starts"
    t.index %i[organization_id professional_id starts_at], name: "idx_appointments_professional_starts"
    # What the engine reads: the blocking slots of a professional that end after the range starts.
    t.index %i[organization_id professional_id blocks_to], name: "idx_appointments_professional_blocks",
      where: "status <> 'cancelled' AND status <> 'rescheduled'"
    t.index %i[organization_id resource_id blocks_to], name: "idx_appointments_resource_blocks",
      where: "resource_id IS NOT NULL AND status <> 'cancelled' AND status <> 'rescheduled'"
  end
end

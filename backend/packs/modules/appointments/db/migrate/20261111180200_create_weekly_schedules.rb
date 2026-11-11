# weekly_schedules: opening hours in the branch's LOCAL wall-clock time (no zone here: the zone is the branch's; a slot never
# crosses midnight). The owner is a branch, a professional or a resource. Tenant table.
#
# The owner is NOT polymorphic: a polymorphic owner_id cannot carry a foreign key, so there is one nullable column per owner
# kind and a CHECK that exactly the matching one is set. That is what lets the database prove, with composite FKs, that
#   - a professional only has hours in a branch where they are assigned, and
#   - a resource only has hours in the branch it belongs to.
#
# Overlaps are refused by three partial EXCLUDE constraints over half-open minute ranges [start, end), so 9-13 and 13-15 do
# not overlap. A professional's constraint ignores the branch: a person is not in two branches at once. The range is built from
# minutes of the day with an IMMUTABLE expression, which is why slots are restricted to whole minutes (a sub-minute slot would
# make an empty range that escapes the exclusion).
class CreateWeeklySchedules < ActiveRecord::Migration[8.1]
  MINUTES = ->(column) { "(EXTRACT(HOUR FROM #{column}) * 60 + EXTRACT(MINUTE FROM #{column}))::int" }
  RANGE = "int4range(#{MINUTES.call('starts_at_local')}, #{MINUTES.call('ends_at_local')}, '[)')".freeze

  def change
    create_tenant_table :weekly_schedules do |t|
      t.tenant_reference :company, index: false
      t.uuid :branch_id, null: false
      t.string :owner_type, null: false
      t.uuid :professional_id
      t.uuid :resource_id
      t.integer :weekday, limit: 2, null: false
      t.time :starts_at_local, null: false
      t.time :ends_at_local, null: false
      t.timestamps

      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_ws_branch"
      # MATCH SIMPLE: not enforced while professional_id / resource_id is NULL (branch and the other owner kind).
      t.foreign_key :professional_branch_assignments, column: %i[organization_id company_id professional_id branch_id],
        primary_key: %i[organization_id company_id professional_id branch_id], name: "fk_ws_assignment"
      t.foreign_key :resources, column: %i[organization_id company_id branch_id resource_id],
        primary_key: %i[organization_id company_id branch_id id], name: "fk_ws_resource"

      t.check_constraint "owner_type = 'branch' OR owner_type = 'professional' OR owner_type = 'resource'", name: "chk_ws_owner_type"
      t.check_constraint "(owner_type = 'branch' AND professional_id IS NULL AND resource_id IS NULL) OR " \
                         "(owner_type = 'professional' AND professional_id IS NOT NULL AND resource_id IS NULL) OR " \
                         "(owner_type = 'resource' AND professional_id IS NULL AND resource_id IS NOT NULL)", name: "chk_ws_owner"
      t.check_constraint "weekday >= 0 AND weekday <= 6", name: "chk_ws_weekday"
      t.check_constraint "starts_at_local < ends_at_local", name: "chk_ws_range"
      t.check_constraint "date_trunc('minute', starts_at_local) = starts_at_local AND date_trunc('minute', ends_at_local) = ends_at_local",
        name: "chk_ws_minute_precision"

      t.exclusion_constraint "branch_id WITH =, weekday WITH =, #{RANGE} WITH &&", using: :gist, where: "owner_type = 'branch'", name: "ex_ws_branch"
      t.exclusion_constraint "professional_id WITH =, weekday WITH =, #{RANGE} WITH &&", using: :gist, where: "professional_id IS NOT NULL", name: "ex_ws_professional"
      t.exclusion_constraint "resource_id WITH =, weekday WITH =, #{RANGE} WITH &&", using: :gist, where: "resource_id IS NOT NULL", name: "ex_ws_resource"

      # The reads of the engine: the hours of a branch for a weekday.
      t.index %i[organization_id branch_id weekday], name: "idx_ws_branch_weekday"
      # The assignment side of the composite FK (deleting an assignment looks here) and "the hours of a professional in a branch".
      t.index %i[professional_id branch_id], where: "professional_id IS NOT NULL", name: "idx_ws_professional_branch"
      # The resource side of the composite FK.
      t.index %i[resource_id branch_id], where: "resource_id IS NOT NULL", name: "idx_ws_resource_branch"
    end
  end
end

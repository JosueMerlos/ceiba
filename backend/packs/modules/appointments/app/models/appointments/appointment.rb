module Appointments
  # A booked slot of a professional at a branch. TENANT table. It holds only what the availability engine reads and has no
  # business validations: creating appointments is the job of a booking use case, not of the model.
  class Appointment < ApplicationRecord
    # Only these statuses give the slot back; every other one (including no_show and completed) still occupies the agenda.
    RELEASING_STATUSES = %w[cancelled rescheduled].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :blocking, -> { where.not(status: RELEASING_STATUSES) }
    # Half-open: a blocking interval that ends exactly at `from`, or starts exactly at `to`, does not overlap.
    scope :overlapping, ->(from, to) { where("blocks_from < ? AND blocks_to > ?", to, from) }
  end
end

module Appointments
  # A booked slot of a professional at a branch. TENANT table. It has no business validations: the database constraints guard
  # the agenda and creating appointments is the job of a booking use case, not of the model.
  class Appointment < ApplicationRecord
    # Only these statuses give the slot back; every other one (including no_show and completed) still occupies the agenda.
    RELEASING_STATUSES = %w[cancelled rescheduled].freeze

    SOURCES = %w[panel public_booking].freeze

    # Closed lists, mirrored by CHECKs: who cancelled and why are codes, never free text.
    CANCELLED_BY = %w[staff customer system].freeze
    CANCELLATION_REASONS = %w[customer_request professional_unavailable business_decision other].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    NOTES_MAX_LENGTH = 500

    # Free text that may reveal something private.
    encrypts :notes

    belongs_to :resource, class_name: "Appointments::Resource", optional: true
    has_many :services_snapshot, -> { order(:position) }, class_name: "Appointments::AppointmentService", inverse_of: :appointment, dependent: nil

    scope :blocking, -> { where.not(status: RELEASING_STATUSES) }
    # Half-open: a blocking interval that ends exactly at `from`, or starts exactly at `to`, does not overlap.
    scope :overlapping, ->(from, to) { where("blocks_from < ? AND blocks_to > ?", to, from) }
  end
end

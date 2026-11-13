module Appointments
  # One service of an appointment as it was booked: duration, buffers and price are copies, so a later catalog change does not
  # rewrite history. TENANT table. Immutable once persisted.
  class AppointmentService < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    belongs_to :appointment, class_name: "Appointments::Appointment", inverse_of: :services_snapshot

    def readonly? = persisted? || super
  end
end

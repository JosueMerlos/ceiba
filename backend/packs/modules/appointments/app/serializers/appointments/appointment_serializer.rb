module Appointments
  # Fields match components.schemas.Appointment EXACTLY. Only the customer's id goes out, never their name or contact data, and the encrypted notes stay out too.
  class AppointmentSerializer < Api::Serializer
    attributes :id, :branch_id, :professional_id, :resource_id, :customer_id, :status, :source, :lock_version, :rescheduled_from_id, :cancelled_by,
               :cancellation_reason

    attribute(:starts_at) { |appointment| appointment.starts_at.utc.iso8601(3) }
    attribute(:ends_at) { |appointment| appointment.ends_at.utc.iso8601(3) }

    attribute :services do |appointment|
      appointment.services_snapshot.map do |line|
        line.slice(:service_id, :position, :duration_minutes, :price_minor, :currency).symbolize_keys
      end
    end

    attribute(:total_price_minor) { |appointment| appointment.services_snapshot.sum(&:price_minor) }
    attribute(:currency) { |appointment| appointment.services_snapshot.first&.currency }
  end
end

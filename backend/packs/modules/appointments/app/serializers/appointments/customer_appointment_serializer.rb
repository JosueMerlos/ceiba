module Appointments
  # Fields match components.schemas.CustomerAppointment EXACTLY. Names come from `params` (loaded once per page, archived
  # records included); notes, prices and the customer's own data stay out.
  class CustomerAppointmentSerializer < Api::Serializer
    attributes :id, :status

    attribute(:starts_at) { |appointment| appointment.starts_at.utc.iso8601(3) }
    attribute(:ends_at) { |appointment| appointment.ends_at.utc.iso8601(3) }

    attribute :professional do |appointment|
      { id: appointment.professional_id, display_name: params.fetch(:professional_names).fetch(appointment.professional_id) }
    end

    attribute :services do |appointment|
      appointment.services_snapshot.map { |line| { service_id: line.service_id, name: params.fetch(:service_names).fetch(line.service_id) } }
    end
  end
end

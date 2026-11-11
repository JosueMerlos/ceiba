module Appointments
  # Fields match components.schemas.Service EXACTLY.
  class ServiceSerializer < Api::Serializer
    attributes :id, :name, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency, :active, :position,
               created_at: :iso8601, updated_at: :iso8601

    attribute(:archived_at) { |service| service.archived_at&.iso8601 }
  end
end

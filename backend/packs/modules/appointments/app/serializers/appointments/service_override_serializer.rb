module Appointments
  # Fields match components.schemas.ServiceOverride EXACTLY. The currency is the service's: an override has none of its own.
  class ServiceOverrideSerializer < Api::Serializer
    attributes :id, :branch_id, :service_id, :duration_minutes, :price_minor, created_at: :iso8601, updated_at: :iso8601

    attribute(:currency) { |override| override.service.currency }
  end
end

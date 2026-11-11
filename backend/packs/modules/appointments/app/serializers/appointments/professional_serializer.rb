module Appointments
  # Fields match components.schemas.Professional EXACTLY. No email or name of the linked user: only its id.
  class ProfessionalSerializer < Api::Serializer
    attributes :id, :display_name, :user_id, :active, :branch_ids, :service_ids, created_at: :iso8601, updated_at: :iso8601

    attribute(:archived_at) { |professional| professional.archived_at&.iso8601 }
  end
end

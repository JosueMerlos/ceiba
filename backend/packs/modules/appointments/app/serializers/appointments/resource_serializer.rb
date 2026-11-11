module Appointments
  # Fields match components.schemas.Resource EXACTLY.
  class ResourceSerializer < Api::Serializer
    attributes :id, :branch_id, :name, :kind, :active, created_at: :iso8601, updated_at: :iso8601

    attribute(:archived_at) { |resource| resource.archived_at&.iso8601 }
  end
end

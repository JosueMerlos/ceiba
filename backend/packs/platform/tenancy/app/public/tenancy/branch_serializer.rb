module Tenancy
  # Public representation of a branch. Fields match components.schemas.Branch EXACTLY.
  class BranchSerializer < Api::Serializer
    attributes :id, :company_id, :name, :time_zone, :address, :phone_e164, :status, created_at: :iso8601, updated_at: :iso8601
  end
end

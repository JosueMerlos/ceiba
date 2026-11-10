module Tenancy
  # Public representation of an organization (public API used by access in its endpoints). Fields match
  # components.schemas.Organization EXACTLY.
  class OrganizationSerializer < Api::Serializer
    attributes :id, :name, :legal_name, :country_code, :status, created_at: :iso8601, updated_at: :iso8601
  end
end

module Tenancy
  # Representación pública de una organización (API pública: la usa access en sus endpoints). Los campos son EXACTAMENTE los de components.schemas.Organization.
  class OrganizationSerializer < Api::Serializer
    attributes :id, :name, :legal_name, :country_code, :status, created_at: :iso8601, updated_at: :iso8601
  end
end

module Tenancy
  # Public representation of a company. Fields match components.schemas.Company EXACTLY. Public API: access (which authorizes
  # the company endpoints) uses it without touching the private model.
  class CompanySerializer < Api::Serializer
    attributes :id, :name, :slug, :business_type, :currency, :locale, :status, created_at: :iso8601, updated_at: :iso8601
  end
end

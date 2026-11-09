module Tenancy
  # Representación pública de una empresa. Los campos son EXACTAMENTE los de components.schemas.Company. Es API pública:
  # access (que autoriza los endpoints de empresa) la usa sin tocar el modelo privado.
  class CompanySerializer < Api::Serializer
    attributes :id, :name, :slug, :business_type, :currency, :locale, :status, created_at: :iso8601, updated_at: :iso8601
  end
end

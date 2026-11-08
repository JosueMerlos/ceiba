module Tenancy
  # Alta de una empresa ADICIONAL en una organización ya provisionada (seeds, back-office M4.01). La primera empresa
  # nace con Tenancy::ProvisionOrganization. Devuelve la empresa; los fallos previstos son Tenancy::ProvisioningFailed.
  #
  #   Tenancy::AddCompany.call(organization:, name:, slug:, business_type:, currency:)
  class AddCompany
    def self.call(organization:, **attributes)
      FailureTranslator.translating(slug: attributes[:slug]) do
        Tenancy.with_context(organization:) { Company.create!(attributes) }
      end
    end
  end
end

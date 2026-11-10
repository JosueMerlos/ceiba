module Tenancy
  # Creates an ADDITIONAL company in an already provisioned organization (seeds, back-office). The first company is born with
  # Tenancy::ProvisionOrganization. Returns the company; expected failures are Tenancy::ProvisioningFailed.
  #
  #   Tenancy::AddCompany.call(organization:, name:, slug:, business_type:, currency:)
  class AddCompany
    def self.call(organization:, **attributes)
      attributes = AllowedAttributes.permit(attributes, AllowedAttributes::COMPANY, :company)
      FailureTranslator.translating(slug: attributes[:slug]) do
        Tenancy.with_context(organization:) { Company.create!(attributes) }
      end
    end
  end
end

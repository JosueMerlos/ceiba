module Tenancy
  # Creates an ADDITIONAL branch for a company; the organization is derived from the company. Returns the branch; expected
  # failures are Tenancy::ProvisioningFailed.
  #
  #   Tenancy::AddBranch.call(company:, name:, time_zone: "America/Managua")
  class AddBranch
    def self.call(company:, **attributes)
      attributes = AllowedAttributes.permit(attributes, AllowedAttributes::BRANCH, :branch)
      FailureTranslator.translating do
        Tenancy.with_context(organization: company.organization, company:) { Branch.create!(attributes.merge(company:)) }
      end
    end
  end
end

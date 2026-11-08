module Tenancy
  # Alta de una sucursal ADICIONAL de una empresa. La organización se deriva de la empresa. Devuelve la sucursal; los
  # fallos previstos son Tenancy::ProvisioningFailed.
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

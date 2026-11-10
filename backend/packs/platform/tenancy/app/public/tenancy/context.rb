module Tenancy
  # Where the code is working right now: organization (the tenant) and optionally company, branch and the acting principal.
  # Immutable: switching company creates a new context (`context.with(company: other)`).
  #
  # Validates coherence on construction and on every `with`, so an inconsistent context never exists:
  #   - the organization is persisted;
  #   - company.organization_id == organization.id;
  #   - branch.company_id == company.id (and a branch requires a company).
  Context = Data.define(:organization, :company, :branch, :principal) do
    def initialize(organization:, company: nil, branch: nil, principal: nil)
      super
      validate!
    end

    private

    def validate!
      raise InconsistentContext, "El contexto requiere una organización guardada" unless organization.is_a?(Tenancy::Organization) && organization.persisted?

      validate_company!
      validate_branch!
    end

    def validate_company!
      return if company.nil? || company.organization_id == organization.id

      raise InconsistentContext, "La empresa #{company.id} no pertenece a la organización #{organization.id}"
    end

    def validate_branch!
      return if branch.nil?
      raise InconsistentContext, "Una sucursal requiere indicar su empresa" if company.nil?
      return if branch.company_id == company.id && branch.organization_id == organization.id

      raise InconsistentContext, "La sucursal #{branch.id} no pertenece a la empresa #{company.id}"
    end
  end
end

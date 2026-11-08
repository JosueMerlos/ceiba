module Tenancy
  # Dónde está trabajando el código ahora mismo: organización (el tenant), y opcionalmente empresa, sucursal y el
  # principal que actúa. Inmutable: cambiar de empresa crea un contexto nuevo (`context.with(company: otra)`).
  #
  # Valida la coherencia al construirse y en cada `with`, así un contexto incoherente no llega a existir:
  #   - la organización existe (está guardada);
  #   - company.organization_id == organization.id;
  #   - branch.company_id == company.id (y una sucursal exige empresa).
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

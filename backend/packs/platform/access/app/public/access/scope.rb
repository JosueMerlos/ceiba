module Access
  # Where a permission is exercised: the organization, a company or a branch (always within ONE organization). Value
  # object: policies build it from the record they authorize (other packs' models are private, so their ids are passed).
  #
  #   Access::Scope.organization(org.id)
  #   Access::Scope.company(organization_id: org.id, company_id: company.id)
  #   Access::Scope.branch(organization_id: org.id, company_id: branch.company_id, branch_id: branch.id)
  Scope = Data.define(:organization_id, :company_id, :branch_id) do
    def self.organization(organization_id) = new(organization_id:, company_id: nil, branch_id: nil)
    def self.company(organization_id:, company_id:) = new(organization_id:, company_id:, branch_id: nil)
    def self.branch(organization_id:, company_id:, branch_id:) = new(organization_id:, company_id:, branch_id:)

    # The scope the request is acting in (Tenancy::Context), at the given level: :company or :branch.
    def self.from_context(context, level:)
      organization_id = context.organization.id
      case level
      when :company then company(organization_id:, company_id: context.company.id)
      when :branch then branch(organization_id:, company_id: context.company.id, branch_id: context.branch.id)
      else raise ArgumentError, "Nivel de alcance desconocido: #{level.inspect}"
      end
    end

    def initialize(organization_id:, company_id: nil, branch_id: nil)
      raise ArgumentError, "Un alcance requiere organization_id" if organization_id.blank?
      raise ArgumentError, "Un alcance de sucursal requiere company_id" if branch_id.present? && company_id.blank?

      super
    end

    def level
      return :branch if branch_id
      return :company if company_id

      :organization
    end
  end
end

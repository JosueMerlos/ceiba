module Access
  # Policy de la organización (Tenancy::Organization). Vive en access y no en tenancy porque access depende de tenancy y no a
  # la inversa (packwerk rechaza ciclos); los controladores la pasan con `policy_class:`.
  class OrganizationPolicy < BasePolicy
    # Listar "mis organizaciones" (selector de contexto): cualquier usuario autenticado; el Scope lo acota a las suyas.
    def index? = principal.kind == :user

    def show? = can?("platform.organization.read", scope_of(record))
    def update? = can?("platform.organization.update", scope_of(record))
    def destroy? = can?("platform.organization.delete", scope_of(record))
    # create? hereda false: una organización nace SOLO con Tenancy::ProvisionOrganization.

    private

    def scope_of(organization) = Access::Scope.organization(organization.id)

    class Scope < BasePolicy::Scope
      def resolve
        return scope.none unless principal.kind == :user

        scope.where(id: principal.organization_ids)
      end
    end
  end
end

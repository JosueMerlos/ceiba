module Access
  module Principal
    # La persona autenticada por una sesión, con los permisos que le dan sus memberships EN LA ORGANIZACIÓN ACTIVA.
    #
    # Ciclo de vida de una request: Access::RouteContext lo construye desde la identidad (Identity::Principal::User), valida
    # la ruta y lo activa (`activate!`) DENTRO de Tenancy.with_context: ahí se hace la ÚNICA consulta de permisos de la
    # request y queda memorizada. Después `can?`, `reach`, `member?`... no tocan la base.
    #
    # Nunca consulta por su cuenta ni cruza organizaciones: sin activar, o con un alcance de otra organización, niega
    # (criterio 4: un usuario con memberships en X e Y solo usa los de la organización de la ruta).
    class User
      include Principal

      attr_reader :id, :email, :full_name, :organization_id

      # `identity_user`: cualquier objeto con id, email y full_name (Identity::Principal::User).
      def initialize(identity_user)
        @id = identity_user.id
        @email = identity_user.email
        @full_name = identity_user.full_name
      end

      def kind = :user

      # Carga (una consulta) los memberships y permisos del usuario en `organization_id`. Exige estar dentro de
      # Tenancy.with_context de ESA organización: así la consulta la acota el tenant y no hay forma de cargar los de otra.
      def activate!(organization_id)
        current = ActsAsTenant.current_tenant&.id
        raise ArgumentError, "activate! exige Tenancy.with_context de la organización #{organization_id} (hay #{current.inspect})" unless current == organization_id

        @organization_id = organization_id
        @grants = Grants.load(user_id: id)
        self
      end

      def active? = !@grants.nil?

      def can?(permission_key, scope)
        Principal.ensure_registered!(permission_key)
        return false unless active? && scope.organization_id == organization_id

        @grants.allows?(permission_key, scope)
      end

      # ¿Tiene algún membership en la organización activa?
      def member? = active? && @grants.member?

      # Visibilidad de las rutas: ¿alguno de sus memberships contiene esta empresa / sucursal (o está dentro de ella)?
      # No es autorización (eso es `can?`): decide 404 (no lo ve) frente a 403 (lo ve pero no puede).
      def sees_company?(company_id) = active? && @grants.sees_company?(company_id)
      def sees_branch?(branch_id, company_id) = active? && @grants.sees_branch?(branch_id, company_id)

      # A qué recursos de la organización activa llega un permiso (Access::Reach), para filtrar listados.
      def reach(permission_key)
        Principal.ensure_registered!(permission_key)
        return Reach.new(organization: false, company_ids: [], branch_ids: []) unless active?

        @grants.reach(permission_key)
      end

      # Organizaciones donde tiene algún membership (selector de contexto, ADR-0028). Cruza tenants A PROPÓSITO: es el único
      # camino y vive en Access::MembershipDirectory (cop Ceiba/TenantBypass, AllowedFiles). Memorizado.
      def organization_ids = @organization_ids ||= MembershipDirectory.organization_ids_for(id)
    end
  end
end

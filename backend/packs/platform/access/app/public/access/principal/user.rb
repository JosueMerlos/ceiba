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
        @active_modules = nil # los módulos activos son de UNA organización: reactivar en otra no puede arrastrar el memo
        @grants = Grants.load(user_id: id, upward_keys: Access.registry.upward_keys, branch_company: ->(branch_id) { Tenancy::Directory.branch_company_id(branch_id) })
        self
      end

      def active? = !@grants.nil?

      def can?(permission_key, scope)
        Principal.ensure_registered!(permission_key)
        return false unless active? && scope.organization_id == organization_id
        return false unless module_allows?(permission_key, scope)

        @grants.allows?(permission_key, scope)
      end

      # ¿Está activo el módulo `module_key` en la empresa? Los módulos que el gate no controla (platform) siempre lo están. Memoizado
      # por principal (una consulta por request, ver Access.module_gate).
      def module_active?(module_key, company_id)
        return true unless Access.module_gate&.gated?(module_key.to_s)

        active_companies(module_key.to_s).include?(company_id)
      end

      # Permisos que ejerce en el contexto (empresa y/o sucursal) y cuyo módulo está activo en esa empresa: lo que /me entrega al
      # frontend para REFLEJAR (no decidir) qué mostrar. Sin empresa en el contexto no hay permisos de módulo.
      def permission_keys_in(company_id: nil, branch_id: nil)
        return [] unless active?

        @grants.keys_within(company_id:, branch_id:).select { |key| Access.registered?(key) && module_active_in_context?(key, company_id) }.sort
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

        restrict_to_active_modules(@grants.reach(permission_key), permission_key)
      end

      # Organizaciones donde tiene algún membership (selector de contexto, ADR-0028). Cruza tenants A PROPÓSITO: es el único
      # camino y vive en Access::MembershipDirectory (cop Ceiba/TenantBypass, AllowedFiles). Memorizado.
      def organization_ids = @organization_ids ||= MembershipDirectory.organization_ids_for(id)

      private

      def module_key_of(permission_key) = Access.registry.fetch(permission_key).module_key

      # El permiso de un módulo controlado exige el módulo activo en la empresa del alcance (en el de organización, en alguna).
      def module_allows?(permission_key, scope)
        module_key = module_key_of(permission_key)
        return true unless Access.module_gate&.gated?(module_key)

        companies = active_companies(module_key)
        scope.company_id ? companies.include?(scope.company_id) : companies.any?
      end

      def module_active_in_context?(permission_key, company_id)
        module_key = module_key_of(permission_key)
        return true unless Access.module_gate&.gated?(module_key)

        company_id.present? && active_companies(module_key).include?(company_id)
      end

      # Un listado de un módulo solo llega a las empresas donde está activo: el alcance de organización se vuelve "esas empresas".
      def restrict_to_active_modules(reach, permission_key)
        module_key = module_key_of(permission_key)
        return reach unless Access.module_gate&.gated?(module_key)

        active = active_companies(module_key)
        return Reach.new(organization: false, company_ids: active.to_a, branch_ids: []) if reach.organization?

        Reach.new(
          organization: false, company_ids: reach.company_ids & active.to_a,
          branch_ids: reach.branch_ids.select { |branch_id| active.include?(@grants.branch_company_id(branch_id)) }
        )
      end

      # { módulo => Set[empresas] }: UNA consulta (la del gate) por principal. Si no hay contexto de tenancy no se puede saber: se
      # niega (conjunto vacío) y NO se memoriza el fallo.
      def active_companies(module_key)
        @active_modules ||= Access.module_gate.active_companies_by_module
        @active_modules.fetch(module_key, Set.new)
      rescue ActsAsTenant::Errors::NoTenantSet
        Set.new
      end
    end
  end
end

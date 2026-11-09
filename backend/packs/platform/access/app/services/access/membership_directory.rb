module Access
  # ÚNICO camino que lee memberships de TODAS las organizaciones: "¿a qué organizaciones pertenece este usuario?" (selector
  # de contexto, ADR-0028; GET /organizations). Es un camino privilegiado explícito: está en AllowedFiles del cop
  # Ceiba/TenantBypass (revisión de CODEOWNERS). Solo LEE y solo devuelve ids de organización del propio usuario.
  #
  # Con RLS activado (M4.03) esta lectura necesitará una política por usuario o el rol de plataforma con BYPASSRLS (tarea de M4.03).
  module MembershipDirectory
    module_function

    def organization_ids_for(user_id)
      ActsAsTenant.without_tenant { Membership.where(user_id:).distinct.pluck(:organization_id) }
    end
  end
end

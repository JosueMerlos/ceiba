# Permisos de la parte de PLATAFORMA de la matriz (docs/architecture/04-access-control.md): organización, empresas,
# sucursales, módulos, branding, usuarios, API keys y reportes consolidados. La matriz es DATO: cada permiso lista los roles
# de sistema que lo reciben. Los permisos de cada módulo de negocio (citas, servicios...) los declara su propio pack (M0.09).
#
# Solo los permisos de organización, empresa y sucursal (lectura) tienen endpoint en M0.08. Los demás se declaran ya para
# que la matriz sea completa y verificable: gestión de módulos (M0.09), de usuarios y roles (M4.01) y de API keys (M4.02).
Rails.application.config.to_prepare do
  Access.register_permissions(
    "platform",
    "platform.organization.read" => { description: "Ver la organización", roles: %w[org_owner org_admin] },
    "platform.organization.update" => { description: "Editar la organización", roles: %w[org_owner org_admin] },
    "platform.organization.manage_billing" => { description: "Gestionar el cobro de la organización", roles: %w[org_owner] },
    "platform.organization.delete" => { description: "Borrar la organización", roles: %w[org_owner] },
    "platform.organization.transfer_ownership" => { description: "Transferir la propiedad de la organización", roles: %w[org_owner] },
    # Decisión de producto (M0.08): todo rol con membership LEE la empresa y la sucursal a las que pertenece (datos básicos: el
    # personal opera la agenda de una sucursal y los necesita). `from_descendants`: un membership de sucursal lee también la empresa
    # de su sucursal. Editar sigue según la matriz.
    "platform.company.read" => { description: "Ver una empresa", from_descendants: true,
                                 roles: %w[org_owner org_admin company_manager branch_manager receptionist professional] },
    "platform.company.create" => { description: "Crear empresas", roles: %w[org_owner org_admin] },
    "platform.company.update" => { description: "Editar una empresa", roles: %w[org_owner org_admin] },
    "platform.branch.read" => { description: "Ver una sucursal", roles: %w[org_owner org_admin company_manager branch_manager receptionist professional] },
    "platform.branch.create" => { description: "Crear sucursales", roles: %w[org_owner org_admin company_manager] },
    "platform.branch.update" => { description: "Editar una sucursal", roles: %w[org_owner org_admin company_manager] },
    "platform.company_module.manage" => { description: "Activar y desactivar módulos de una empresa", roles: %w[org_owner org_admin] },
    "platform.branding.update" => { description: "Editar el branding de una empresa", roles: %w[org_admin company_manager] },
    # Qué roles puede otorgar cada quien (p. ej. org_admin no invita org_admin) lo decide la invitación (M4.01), no el permiso.
    "platform.user.invite" => { description: "Invitar usuarios", roles: %w[org_owner org_admin company_manager branch_manager] },
    "platform.api_key.manage" => { description: "Gestionar API keys", roles: %w[org_owner org_admin] },
    "platform.reports.consolidated" => { description: "Ver reportes consolidados (solo conteos)", roles: %w[org_owner org_admin] }
  )
end

# Permissions of the PLATFORM part of the role matrix: organization, companies, branches, modules, branding, users,
# API keys and consolidated reports. The matrix is DATA: each permission lists the system roles that receive it.
# Each business module's permissions (appointments, services...) are declared by its own pack.
#
# Only the organization, company and branch (read) permissions have an endpoint so far. The rest are declared already so
# the matrix is complete and verifiable.
Rails.application.config.to_prepare do
  Access.register_permissions(
    "platform",
    "platform.organization.read" => { description: "Ver la organización", roles: %w[org_owner org_admin] },
    "platform.organization.update" => { description: "Editar la organización", roles: %w[org_owner org_admin] },
    "platform.organization.manage_billing" => { description: "Gestionar el cobro de la organización", roles: %w[org_owner] },
    "platform.organization.delete" => { description: "Borrar la organización", roles: %w[org_owner] },
    "platform.organization.transfer_ownership" => { description: "Transferir la propiedad de la organización", roles: %w[org_owner] },
    # Product decision: every role with a membership READS the company and branch it belongs to (basic data: staff run a
    # branch's schedule and need it). `from_descendants`: a branch membership also reads its branch's company.
    # Editing follows the matrix.
    "platform.company.read" => { description: "Ver una empresa", from_descendants: true,
                                 roles: %w[org_owner org_admin company_manager branch_manager receptionist professional] },
    "platform.company.create" => { description: "Crear empresas", roles: %w[org_owner org_admin] },
    "platform.company.update" => { description: "Editar una empresa", roles: %w[org_owner org_admin] },
    "platform.branch.read" => { description: "Ver una sucursal", roles: %w[org_owner org_admin company_manager branch_manager receptionist professional] },
    "platform.branch.create" => { description: "Crear sucursales", roles: %w[org_owner org_admin company_manager] },
    "platform.branch.update" => { description: "Editar una sucursal", roles: %w[org_owner org_admin company_manager] },
    "platform.company_module.manage" => { description: "Activar y desactivar módulos de una empresa", roles: %w[org_owner org_admin] },
    "platform.branding.update" => { description: "Editar el branding de una empresa", roles: %w[org_admin company_manager] },
    # Which roles each inviter may grant (e.g. org_admin cannot invite org_admin) is decided by the invitation, not the permission.
    "platform.user.invite" => { description: "Invitar usuarios", roles: %w[org_owner org_admin company_manager branch_manager] },
    "platform.api_key.manage" => { description: "Gestionar API keys", roles: %w[org_owner org_admin] },
    "platform.reports.consolidated" => { description: "Ver reportes consolidados (solo conteos)", roles: %w[org_owner org_admin] }
  )
end

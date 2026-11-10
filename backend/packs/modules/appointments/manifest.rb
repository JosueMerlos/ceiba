# Minimal appointments module manifest: permissions, role grants, API scopes and settings only. No models or endpoints yet.
#
# The module registry loads this file by PATH and validates it at boot, so it holds only strings and data and references no
# constant from another pack (the file is excluded from Packwerk).
Modules.define :appointments do
  name        "Citas"
  version     "1.0"
  requires    []
  platform    %i[customers notifications]

  permissions do
    permission "appointments.appointment.read",       description: "Ver citas"
    permission "appointments.appointment.create",     description: "Crear citas"
    permission "appointments.appointment.update",     description: "Editar, mover y cancelar citas"
    permission "appointments.appointment.update_own", description: "Editar las propias citas (profesional)"
    permission "appointments.appointment.count",      description: "Ver conteos de citas (sin detalle)"
    permission "appointments.service.read",           description: "Ver servicios y precios"
    permission "appointments.service.manage",         description: "Gestionar servicios y precios"
  end

  # org_owner and org_admin only see appointment COUNTS, never the detail.
  role_grants do
    grant :org_owner,       %w[appointments.appointment.count]
    grant :org_admin,       %w[appointments.appointment.count]
    grant :company_manager, %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.appointment.count appointments.service.read appointments.service.manage]
    grant :branch_manager,  %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.appointment.count appointments.service.read]
    grant :receptionist,    %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.service.read]
    grant :professional,    %w[appointments.appointment.read appointments.appointment.update_own appointments.service.read]
  end

  api_scopes "read:appointments"  => %w[appointments.appointment.read appointments.service.read],
             "write:appointments" => %w[appointments.appointment.create appointments.appointment.update]

  settings_schema "config/settings.schema.json"
  settings_levels %i[company branch]

  # No events yet; `publishes` requires a registered schema for each event once the domain adds them.
  publishes   []
  subscribes  { }

  navigation  [ { key: "agenda", path: "/agenda", permission: "appointments.appointment.read" },
                { key: "summary", path: "/agenda/summary", permission: "appointments.appointment.count" } ]
end

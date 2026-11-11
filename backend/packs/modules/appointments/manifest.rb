# Appointments module manifest: permissions, role grants, API scopes, settings and navigation of the module.
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
    # from_descendants: services are company records, and branch roles read the catalog they work with.
    permission "appointments.service.read",           description: "Ver servicios y precios", from_descendants: true
    permission "appointments.service.manage",         description: "Gestionar servicios y precios"
    permission "appointments.service.override_duration", description: "Cambiar la duración de un servicio en una sucursal"
    permission "appointments.service.override_price",    description: "Cambiar el precio de un servicio en una sucursal"
    # Professionals are company records read from the branch (from_descendants); the person's own profile is asked in the
    # branch where they are assigned, so read_own is not upward.
    permission "appointments.professional.read",      description: "Ver profesionales, sus sucursales y servicios", from_descendants: true
    permission "appointments.professional.manage",    description: "Crear, editar y archivar profesionales y definir los servicios que prestan"
    permission "appointments.professional.assign",    description: "Asignar profesionales a una sucursal"
    permission "appointments.professional.read_own",  description: "Ver el propio perfil de profesional"
    permission "appointments.resource.read",          description: "Ver los recursos de una sucursal"
    permission "appointments.resource.manage",        description: "Gestionar los recursos de una sucursal"
    permission "appointments.schedule.read",          description: "Ver los horarios de la sucursal, de los profesionales y de los recursos"
    permission "appointments.schedule.manage",        description: "Gestionar los horarios de la sucursal, de los profesionales y de los recursos"
    permission "appointments.schedule.read_own",      description: "Ver el propio horario (profesional)"
    permission "appointments.time_off.read",          description: "Ver las ausencias de profesionales y recursos"
    permission "appointments.time_off.manage",        description: "Gestionar las ausencias de profesionales y recursos"
    permission "appointments.time_off.manage_own",    description: "Ver, crear y borrar las propias ausencias (profesional)"
  end

  # org_owner and org_admin only see appointment COUNTS, never the detail.
  role_grants do
    grant :org_owner,       %w[appointments.appointment.count]
    grant :org_admin,       %w[appointments.appointment.count]
    grant :company_manager, %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.appointment.count appointments.service.read appointments.service.manage
                               appointments.service.override_duration appointments.service.override_price
                               appointments.professional.read appointments.professional.manage appointments.professional.assign
                               appointments.resource.read appointments.resource.manage appointments.schedule.read
                               appointments.schedule.manage appointments.time_off.read appointments.time_off.manage]
    grant :branch_manager,  %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.appointment.count appointments.service.read appointments.service.override_duration
                               appointments.professional.read appointments.professional.assign appointments.resource.read
                               appointments.resource.manage appointments.schedule.read appointments.schedule.manage
                               appointments.time_off.read appointments.time_off.manage]
    grant :receptionist,    %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.service.read appointments.professional.read appointments.resource.read
                               appointments.schedule.read appointments.time_off.read]
    grant :professional,    %w[appointments.appointment.read appointments.appointment.update_own appointments.service.read
                               appointments.professional.read_own appointments.resource.read appointments.schedule.read_own
                               appointments.time_off.manage_own]
  end

  api_scopes "read:appointments"  => %w[appointments.appointment.read appointments.service.read],
             "write:appointments" => %w[appointments.appointment.create appointments.appointment.update]

  # Branches that exist when the module is enabled get the default opening hours.
  on_enable "Appointments::Lifecycle::OnEnable"

  settings_schema "config/settings.schema.json"
  settings_levels %i[company branch]

  # No events yet; `publishes` requires a registered schema for each event once the domain adds them.
  publishes   []
  subscribes  { }

  navigation  [ { key: "agenda", path: "/agenda", permission: "appointments.appointment.read" },
                { key: "summary", path: "/agenda/summary", permission: "appointments.appointment.count" } ]
end

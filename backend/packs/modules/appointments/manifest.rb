# Manifiesto MÍNIMO del módulo de citas (M0.09): permisos, concesiones, scopes y settings de docs/domain/appointments.md. Sin
# modelos ni endpoints todavía (el dominio llega en F1): la provisión lo activa por defecto y /api/v1/me lo reporta.
#
# El registro (platform/modules) carga este archivo por ARCHIVO y lo valida al arrancar; aquí solo hay cadenas y datos, ninguna
# constante de otro pack (este archivo está excluido de packwerk, docs/architecture/02-modular-monolith.md).
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
    permission "appointments.service.read",           description: "Ver servicios y precios"
    permission "appointments.service.manage",         description: "Gestionar servicios y precios"
  end

  # La matriz de docs/architecture/04-access-control.md: org_owner y org_admin solo ven conteos (platform.reports.consolidated).
  role_grants do
    grant :company_manager, %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.service.read appointments.service.manage]
    grant :branch_manager,  %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.service.read]
    grant :receptionist,    %w[appointments.appointment.read appointments.appointment.create appointments.appointment.update
                               appointments.service.read]
    grant :professional,    %w[appointments.appointment.read appointments.appointment.update_own appointments.service.read]
  end

  api_scopes "read:appointments"  => %w[appointments.appointment.read appointments.service.read],
             "write:appointments" => %w[appointments.appointment.create appointments.appointment.update]

  settings_schema "config/settings.schema.json"
  settings_levels %i[company branch]

  # Los eventos appointments.*.v1 y sus esquemas llegan con el dominio (F1); `publishes` exige un esquema registrado por cada uno.
  publishes   []
  subscribes  { }

  navigation  [ { key: "agenda", path: "/agenda", permission: "appointments.appointment.read" } ]
end

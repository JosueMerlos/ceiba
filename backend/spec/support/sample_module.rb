# Módulos FICTICIOS para los specs del sistema de módulos (M0.09): `sample` y `sample_addon` (que lo requiere). Existen SOLO en la
# suite, para no adelantar `appointments`: se declaran con la misma `Modules.define` que usa un manifiesto real y quedan en el
# registro global, con sus permisos registrados en access (spec/support/access_catalog.rb los sincroniza al arrancar).
#
# Sus hooks son espías: `SampleModule.calls` cuenta lo que ejecutaron Enable y Disable.
module SampleModule
  SCHEMA = {
    type: "object",
    properties: {
      min_lead_time_minutes: { type: "integer", minimum: 0, default: 120 },
      max_advance_days: { type: "integer", minimum: 1, default: 60 },
      cancellation_window_hours: { type: "integer", minimum: 0, default: 4, "x-levels": %w[company] },
      public_booking_enabled: { type: "boolean", default: true }
    }
  }.freeze

  class << self
    def calls = @calls ||= []
    def reset! = @calls = []
  end

  class OnEnable
    def self.call(company:) = SampleModule.calls << [ :enable, company.id ]
  end

  class OnDisable
    def self.call(company:) = SampleModule.calls << [ :disable, company.id ]
  end
end

Modules.define :sample do
  name "Muestra"
  version "1.0"
  permissions do
    permission "sample.thing.read", description: "Ver cosas de muestra"
    permission "sample.thing.manage", description: "Gestionar cosas de muestra"
  end
  role_grants do
    grant :company_manager, all: true
    grant :receptionist, %w[sample.thing.read]
  end
  settings_schema SampleModule::SCHEMA
  settings_levels %i[company branch]
  navigation [ { key: "things", path: "/things", permission: "sample.thing.read" } ]
  on_enable "SampleModule::OnEnable"
  on_disable "SampleModule::OnDisable"
end

Modules.define :sample_addon do
  name "Complemento de muestra"
  version "1.0"
  requires %i[sample]
  permissions { permission "sample_addon.extra.read", description: "Ver extras de muestra" }
  role_grants { grant :company_manager, all: true }
end
Modules.registry.validate!

RSpec.configure { |config| config.before { SampleModule.reset! } }

# FICTITIOUS modules for the module system specs: `sample` and `sample_addon` (which requires it). They exist ONLY in the
# suite, so as not to anticipate `appointments`: declared with the same `Modules.define` a real manifest uses and left in
# the global registry, with their permissions registered in access (spec/support/access_catalog.rb syncs them at boot).
#
# Their hooks are spies: `SampleModule.calls` counts what Enable and Disable ran.
module SampleModule
  SCHEMA = {
    type: "object",
    properties: {
      min_lead_time_minutes: { type: "integer", minimum: 0, maximum: 525_600, default: 120 },
      max_advance_days: { type: "integer", minimum: 1, maximum: 730, default: 60 },
      cancellation_window_hours: { type: "integer", minimum: 0, maximum: 720, default: 4, "x-levels": %w[company] },
      public_booking_enabled: { type: "boolean", default: true }
    }
  }.freeze

  class << self
    def calls = @calls ||= []
    # What each on_enable run was told about being the company's first activation of the module.
    def first_activations = @first_activations ||= []
    def reset! = (@calls = []; @first_activations = [])
  end

  class OnEnable
    def self.call(company:, first_activation:)
      SampleModule.calls << [ :enable, company.id ]
      SampleModule.first_activations << first_activation
    end
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

require "rails_helper"

RSpec.describe "Manifiesto de appointments" do
  subject(:manifest) { Modules.registry.fetch("appointments") }

  it "es el módulo de citas, sin dependencias" do
    expect(manifest).to have_attributes(key: "appointments", name: "Citas", version: "1.0", requires: [])
  end

  it "declara los permisos de la matriz de 04 con el prefijo del módulo" do
    expect(manifest.permission_keys).to contain_exactly(
      "appointments.appointment.read", "appointments.appointment.create", "appointments.appointment.update",
      "appointments.appointment.update_own", "appointments.appointment.count", "appointments.service.read", "appointments.service.manage",
      "appointments.service.override_duration", "appointments.service.override_price",
      "appointments.professional.read", "appointments.professional.manage", "appointments.professional.assign", "appointments.professional.read_own",
      "appointments.resource.read", "appointments.resource.manage",
      "appointments.schedule.read", "appointments.schedule.manage", "appointments.schedule.read_own",
      "appointments.time_off.read", "appointments.time_off.manage", "appointments.time_off.manage_own"
    )
  end

  it "concede según la matriz: el personal opera citas, el profesional solo las suyas, solo company_manager gestiona servicios" do
    expect(manifest.role_grants).to include(
      "company_manager" => include("appointments.service.manage", "appointments.appointment.update",
                                   "appointments.service.override_duration", "appointments.service.override_price"),
      "branch_manager" => include("appointments.appointment.create", "appointments.service.override_duration")
        .and(satisfy { |keys| keys.exclude?("appointments.service.manage") && keys.exclude?("appointments.service.override_price") }),
      "receptionist" => include("appointments.appointment.create", "appointments.service.read"),
      "professional" => include("appointments.appointment.read", "appointments.appointment.update_own", "appointments.service.read")
    )
  end

  it "el profesional solo ve su perfil y su horario, gestiona sus ausencias y lee los recursos: nada de gestión ajena" do
    expect(manifest.role_grants.fetch("professional")).to contain_exactly(
      "appointments.appointment.read", "appointments.appointment.update_own", "appointments.service.read",
      "appointments.professional.read_own", "appointments.resource.read", "appointments.schedule.read_own", "appointments.time_off.manage_own"
    )
  end

  it "la recepción solo lee profesionales, recursos, horarios y ausencias" do
    expect(manifest.role_grants.fetch("receptionist")).to include(
      "appointments.professional.read", "appointments.resource.read", "appointments.schedule.read", "appointments.time_off.read"
    ).and(satisfy { |keys| keys.grep(/\.(manage|assign|manage_own|read_own)\z/).empty? })
  end

  it "solo company_manager gestiona profesionales; la sucursal asigna, gestiona recursos, horarios y ausencias (04)", :aggregate_failures do
    holders = ->(key) { manifest.role_grants.select { |_role, keys| keys.include?(key) }.keys }

    expect(holders.call("appointments.professional.manage")).to contain_exactly("company_manager")
    expect(holders.call("appointments.professional.assign")).to contain_exactly("company_manager", "branch_manager")
    expect(holders.call("appointments.professional.read")).to contain_exactly("company_manager", "branch_manager", "receptionist")
    expect(holders.call("appointments.professional.read_own")).to contain_exactly("professional")
    expect(holders.call("appointments.resource.manage")).to contain_exactly("company_manager", "branch_manager")
    expect(holders.call("appointments.resource.read")).to contain_exactly("company_manager", "branch_manager", "receptionist", "professional")
    expect(holders.call("appointments.schedule.manage")).to contain_exactly("company_manager", "branch_manager")
    expect(holders.call("appointments.schedule.read")).to contain_exactly("company_manager", "branch_manager", "receptionist")
    expect(holders.call("appointments.schedule.read_own")).to contain_exactly("professional")
    expect(holders.call("appointments.time_off.manage")).to contain_exactly("company_manager", "branch_manager")
    expect(holders.call("appointments.time_off.read")).to contain_exactly("company_manager", "branch_manager", "receptionist")
    expect(holders.call("appointments.time_off.manage_own")).to contain_exactly("professional")
  end

  it "solo company_manager y branch_manager tocan overrides: la duración los dos, el precio solo company_manager (04)" do
    holders = ->(key) { manifest.role_grants.select { |_role, keys| keys.include?(key) }.keys }

    expect(holders.call("appointments.service.override_duration")).to contain_exactly("company_manager", "branch_manager")
    expect(holders.call("appointments.service.override_price")).to contain_exactly("company_manager")
  end

  it "la lectura de servicios se ejerce también desde la sucursal (from_descendants); la gestión no" do
    expect(Access.registry.upward_keys).to include("appointments.service.read")
    expect(Access.registry.upward_keys).not_to include("appointments.service.manage", "appointments.service.override_price")
  end

  it "los profesionales se leen también desde la sucursal (from_descendants); la gestión, la asignación y lo propio no" do
    expect(Access.registry.upward_keys).to include("appointments.professional.read")
    expect(Access.registry.upward_keys).not_to include(
      "appointments.professional.manage", "appointments.professional.assign", "appointments.professional.read_own",
      "appointments.time_off.manage_own", "appointments.schedule.read_own"
    )
  end

  it "org_owner y org_admin solo ven CONTEOS de citas (04: citas = conteos), nunca el detalle" do
    expect(manifest.role_grants.slice("org_owner", "org_admin").values).to all(eq([ "appointments.appointment.count" ]))
    expect(manifest.role_grants.keys).to include("org_owner", "org_admin")
  end

  it "los scopes de API traducen a permisos del módulo" do
    expect(manifest.api_scopes).to eq(
      "read:appointments" => %w[appointments.appointment.read appointments.service.read],
      "write:appointments" => %w[appointments.appointment.create appointments.appointment.update]
    )
  end

  it "los settings por defecto son los de docs/domain/appointments.md" do
    expect(manifest.defaults).to eq(
      "min_lead_time_minutes" => 120, "max_advance_days" => 60, "slot_step_minutes" => 15, "cancellation_window_hours" => 4,
      "public_booking_enabled" => true, "any_professional_policy" => "least_busy",
      "reminders" => [ { "kind" => "24h", "offset_minutes" => 1440 }, { "kind" => "2h", "offset_minutes" => 120 } ]
    )
  end

  it "los niveles de cada setting son los de la tabla del dominio" do
    company_only = %w[cancellation_window_hours any_professional_policy reminders]

    expect(manifest.setting_keys.select { |key| manifest.levels_for(key) == %w[company] }).to match_array(company_only)
    expect(manifest.levels_for("min_lead_time_minutes")).to eq(%w[company branch])
  end

  it "tiene navegación hacia la agenda, protegida por permiso" do
    expect(manifest.navigation).to include(
      { key: "agenda", path: "/agenda", permission: "appointments.appointment.read" },
      { key: "summary", path: "/agenda/summary", permission: "appointments.appointment.count" }
    )
  end

  it "no publica eventos todavía (sus esquemas llegan con el dominio, F1)" do
    expect(manifest.publishes).to be_empty
  end
end

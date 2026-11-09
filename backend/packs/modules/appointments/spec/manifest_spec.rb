require "rails_helper"

# Manifiesto MÍNIMO de appointments (M0.09): permisos y settings de docs/domain/appointments.md. Sin modelos ni endpoints: la
# provisión lo activa y /me lo reporta; el dominio llega en F1.
RSpec.describe "Manifiesto de appointments" do
  subject(:manifest) { Modules.registry.fetch("appointments") }

  it "es el módulo de citas, sin dependencias" do
    expect(manifest).to have_attributes(key: "appointments", name: "Citas", version: "1.0", requires: [])
  end

  it "declara los permisos de la matriz de 04 con el prefijo del módulo" do
    expect(manifest.permission_keys).to contain_exactly(
      "appointments.appointment.read", "appointments.appointment.create", "appointments.appointment.update",
      "appointments.appointment.update_own", "appointments.appointment.count", "appointments.service.read", "appointments.service.manage"
    )
  end

  it "concede según la matriz: el personal opera citas, el profesional solo las suyas, solo company_manager gestiona servicios" do
    expect(manifest.role_grants).to include(
      "company_manager" => include("appointments.service.manage", "appointments.appointment.update"),
      "branch_manager" => include("appointments.appointment.create").and(satisfy { |keys| keys.exclude?("appointments.service.manage") }),
      "receptionist" => include("appointments.appointment.create", "appointments.service.read"),
      "professional" => contain_exactly("appointments.appointment.read", "appointments.appointment.update_own", "appointments.service.read")
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

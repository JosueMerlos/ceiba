require "rails_helper"

# Criterio de la tarea "Sincronización de permisos": los permisos y las concesiones de los manifiestos llegan a la base por el
# Access.sync! existente (con sus salvaguardas), no por un camino paralelo.
RSpec.describe "Sincronización de permisos desde los manifiestos" do
  def granted(role_key)
    Access::RolePermission.joins(:role).where(roles: { key: role_key }).pluck(:permission_key)
  end

  before { Access.sync!(allow_prune: true) }

  it "persiste los permisos de appointments con su module_key" do
    expect(Access::Permission.where(module_key: "appointments").pluck(:key)).to match_array(Modules.registry.fetch("appointments").permission_keys)
  end

  it "persiste las concesiones de role_grants (company_manager recibe lo que su concesión declara, professional solo lo suyo)" do
    expect(granted("company_manager")).to include("appointments.appointment.create", "appointments.service.manage")
    expect(granted("professional")).to include("appointments.appointment.update_own").and(satisfy { |keys| keys.exclude?("appointments.appointment.create") })
  end

  it "los roles de organización solo reciben de citas el permiso de conteos (matriz de 04)" do
    appointments = (granted("org_owner") + granted("org_admin")).grep(/\Aappointments\./)

    expect(appointments.uniq).to eq([ "appointments.appointment.count" ])
  end

  it "es idempotente" do
    expect { 2.times { Access.sync! } }.not_to change(Access::RolePermission, :count)
  end

  it "conserva la salvaguarda de Access.sync!: quitar un permiso de un manifiesto exige autorizar la retirada" do
    stale = Access::Permission.create!(key: "appointments.fantasma.read", module_key: "appointments", description: "Ya no se declara")

    expect { Access.sync! }.to raise_error(Access::SyncRefused, /appointments\.fantasma\.read/)
    expect(Access::Permission.exists?(stale.key)).to be(true)

    Access.sync!(allow_prune: true)

    expect(Access::Permission.exists?(stale.key)).to be(false)
  end
end

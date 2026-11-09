require "rails_helper"

# Access.register_permissions: la API con la que cada pack declara sus permisos (ADR-0008). Aquí se prueba con un registro
# propio (Access::PermissionRegistry.new) para no tocar el global.
RSpec.describe "Access.register_permissions" do
  let(:permission_registry) { Access::PermissionRegistry.new }

  def register(module_key = "appointments", permissions = { "appointments.appointment.create" => { description: "Crear citas", roles: %w[receptionist] } })
    permission_registry.register(module_key, permissions)
  end

  it "registra los permisos con su descripción y los roles de sistema que los reciben" do
    register

    expect(permission_registry.fetch("appointments.appointment.create")).to have_attributes(
      module_key: "appointments", description: "Crear citas", roles: %w[receptionist]
    )
    expect(permission_registry.keys).to eq([ "appointments.appointment.create" ])
  end

  it "es idempotente: volver a registrar el mismo módulo (recarga de desarrollo) reemplaza, no duplica" do
    register
    register("appointments", { "appointments.appointment.create" => { description: "Crear citas v2", roles: %w[receptionist branch_manager] } })

    expect(permission_registry.keys.size).to eq(1)
    expect(permission_registry.fetch("appointments.appointment.create").roles).to eq(%w[receptionist branch_manager])
  end

  it "rechaza una clave que no sigue <modulo>.<recurso>.<accion>" do
    expect { register("appointments", { "appointments.create" => { description: "x", roles: [] } }) }.to raise_error(ArgumentError, /appointments\.create/)
  end

  it "rechaza una clave cuyo prefijo no es el módulo que la declara" do
    expect { register("appointments", { "billing.invoice.create" => { description: "x", roles: [] } }) }
      .to raise_error(ArgumentError, /billing\.invoice\.create.*appointments/)
  end

  it "rechaza un rol que no es de sistema" do
    expect { register("appointments", { "appointments.appointment.create" => { description: "x", roles: %w[jefe_supremo] } }) }
      .to raise_error(ArgumentError, /jefe_supremo/)
  end

  it "rechaza una descripción vacía y claves repetidas entre módulos" do
    expect { register("appointments", { "appointments.appointment.create" => { description: " ", roles: [] } }) }.to raise_error(ArgumentError, /descripci/)

    register
    clone = Access::PermissionRegistry.new
    clone.register("billing", { "billing.invoice.create" => { description: "x", roles: [] } })
    expect { clone.register("appointments", { "billing.invoice.create" => { description: "x", roles: [] } }) }.to raise_error(ArgumentError)
  end

  it "exige un hash de permisos con opciones conocidas" do
    expect { register("appointments", { "appointments.appointment.create" => { description: "x", roles: [], rol: [] } }) }.to raise_error(ArgumentError, /rol/)
  end

  it "from_descendants marca un permiso de lectura que un membership de sucursal ejerce también sobre su empresa" do
    register("appointments", { "appointments.appointment.read" => { description: "Ver", roles: %w[receptionist], from_descendants: true } })

    expect(permission_registry.fetch("appointments.appointment.read").from_descendants).to be(true)
    expect(permission_registry.upward_keys).to eq([ "appointments.appointment.read" ])
  end

  it "el registro global expone las mismas operaciones a través de Access" do
    expect(Access.permission_keys).to include("platform.branch.read")
    expect(Access.registered?("platform.branch.read")).to be(true)
    expect(Access.registered?("platform.nada.existe")).to be(false)
  end
end

require "rails_helper"

# Access.sync! lleva el registro en memoria (permisos declarados por los packs) a la BASE: permisos, roles de sistema y
# role_permissions. Se ejecuta en cada despliegue y es idempotente (ADR-0008).
RSpec.describe "Access.sync!" do
  let(:permission_registry) do
    Access::PermissionRegistry.new.tap do |permission_registry|
      permission_registry.register("demo", {
        "demo.cosa.read" => { description: "Ver cosas", roles: %w[org_owner receptionist] },
        "demo.cosa.write" => { description: "Editar cosas", roles: %w[org_owner] }
      })
    end
  end

  def keys_of(role_key) = Access::Role.find_by!(key: role_key).role_permissions.pluck(:permission_key).sort

  describe "roles de sistema" do
    it "existen los seis con el alcance de la matriz (04-access-control)" do
      expect(Access::Role.where(system: true).pluck(:key, :scope_level).to_h).to eq(
        "org_owner" => "organization", "org_admin" => "organization", "company_manager" => "company",
        "branch_manager" => "branch", "receptionist" => "branch", "professional" => "branch"
      )
    end
  end

  describe "permisos" do
    it "carga en la base los permisos declarados con su módulo y descripción" do
      Access.sync!(permission_registry)

      expect(Access::Permission.find("demo.cosa.read")).to have_attributes(module_key: "demo", description: "Ver cosas")
      expect(Access::Permission.where(module_key: "demo").pluck(:key)).to contain_exactly("demo.cosa.read", "demo.cosa.write")
    end

    it "asigna a cada rol de sistema exactamente los permisos que se le declararon" do
      Access.sync!(permission_registry)

      expect(keys_of("receptionist")).to eq([ "demo.cosa.read" ])
      expect(keys_of("org_owner")).to eq([ "demo.cosa.read", "demo.cosa.write" ])
      expect(keys_of("professional")).to be_empty
    end

    it "es idempotente: una segunda ejecución no cambia nada" do
      Access.sync!(permission_registry)

      expect { Access.sync!(permission_registry) }.not_to change { [ Access::Permission.count, Access::Role.count, Access::RolePermission.count ] }
    end

    it "reconcilia: un permiso retirado de un rol, o del registro, desaparece de la base" do
      Access.sync!(permission_registry)
      slimmer = Access::PermissionRegistry.new
      slimmer.register("demo", { "demo.cosa.read" => { description: "Ver cosas (v2)", roles: %w[org_owner] } })

      Access.sync!(slimmer)

      expect(Access::Permission.exists?("demo.cosa.write")).to be(false)
      expect(keys_of("receptionist")).to be_empty
      expect(Access::Permission.find("demo.cosa.read").description).to eq("Ver cosas (v2)")
    end

    it "el registro es la fuente de verdad: lo que ya no está registrado se elimina de la base" do
      other = Access::PermissionRegistry.new
      other.register("otro", { "otro.cosa.read" => { description: "x", roles: %w[org_admin] } })
      Access.sync!(permission_registry)
      Access.sync!(other)

      expect(Access::Permission.pluck(:key)).to contain_exactly("otro.cosa.read")
    end
  end

  describe "el registro global (lo que hacen los packs al arrancar)" do
    it "la base contiene exactamente los permisos registrados" do
      expect(Access::Permission.pluck(:key).sort).to eq(Access.permission_keys.sort)
    end
  end
end

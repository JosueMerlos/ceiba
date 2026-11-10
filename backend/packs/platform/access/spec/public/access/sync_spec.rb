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

  # Deja la base EXACTAMENTE como el registro dado (la suite arranca con el catálogo real, que un registro de prueba retiraría).
  def prime(registry) = Access.sync!(registry, allow_prune: true)

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
      prime(permission_registry)

      expect(Access::Permission.find("demo.cosa.read")).to have_attributes(module_key: "demo", description: "Ver cosas")
      expect(Access::Permission.where(module_key: "demo").pluck(:key)).to contain_exactly("demo.cosa.read", "demo.cosa.write")
    end

    it "asigna a cada rol de sistema exactamente los permisos que se le declararon" do
      prime(permission_registry)

      expect(keys_of("receptionist")).to eq([ "demo.cosa.read" ])
      expect(keys_of("org_owner")).to eq([ "demo.cosa.read", "demo.cosa.write" ])
      expect(keys_of("professional")).to be_empty
    end

    it "es idempotente: una segunda ejecución no cambia nada" do
      prime(permission_registry)

      expect { prime(permission_registry) }.not_to change { [ Access::Permission.count, Access::Role.count, Access::RolePermission.count ] }
    end

    it "reconcilia: un permiso retirado de un rol, o del registro, desaparece de la base" do
      prime(permission_registry)
      slimmer = Access::PermissionRegistry.new
      slimmer.register("demo", { "demo.cosa.read" => { description: "Ver cosas (v2)", roles: %w[org_owner] } })

      Access.sync!(slimmer, allow_prune: true)

      expect(Access::Permission.exists?("demo.cosa.write")).to be(false)
      expect(keys_of("receptionist")).to be_empty
      expect(Access::Permission.find("demo.cosa.read").description).to eq("Ver cosas (v2)")
    end

    it "el registro es la fuente de verdad: lo que ya no está registrado se elimina de la base" do
      other = Access::PermissionRegistry.new
      other.register("otro", { "otro.cosa.read" => { description: "x", roles: %w[org_admin] } })
      prime(permission_registry)
      Access.sync!(other, allow_prune: true)

      expect(Access::Permission.pluck(:key)).to contain_exactly("otro.cosa.read")
    end
  end

  describe "red de seguridad: sync! no borra a ciegas" do
    def sync_quietly(registry, **options) = Access.sync!(registry, **options)

    it "aborta si el registro está vacío (nada declarado = un arranque que no cargó los packs, no 'borra todo')" do
      prime(permission_registry)

      expect { sync_quietly(Access::PermissionRegistry.new) }.to raise_error(Access::SyncRefused, /vacío/)
      expect(Access::Permission.exists?("demo.cosa.read")).to be(true)
    end

    it "aborta, sin cambiar nada, si retiraría permisos o concesiones y no se autorizó" do
      prime(permission_registry)
      slimmer = Access::PermissionRegistry.new
      slimmer.register("demo", { "demo.cosa.read" => { description: "Ver", roles: %w[org_owner] } })

      expect { sync_quietly(slimmer) }.to raise_error(Access::SyncRefused, /demo\.cosa\.write.*ACCESS_SYNC_ALLOW_PRUNE/m)
      expect(Access::Permission.exists?("demo.cosa.write")).to be(true)
      expect(keys_of("receptionist")).to eq([ "demo.cosa.read" ])
    end

    it "retira con allow_prune: true o con ACCESS_SYNC_ALLOW_PRUNE=1" do
      prime(permission_registry)
      slimmer = Access::PermissionRegistry.new
      slimmer.register("demo", { "demo.cosa.read" => { description: "Ver", roles: %w[org_owner] } })

      stub_const("ENV", ENV.to_hash.merge("ACCESS_SYNC_ALLOW_PRUNE" => "1"))
      sync_quietly(slimmer)

      expect(Access::Permission.exists?("demo.cosa.write")).to be(false)
    end

    it "una sincronización que solo AÑADE no necesita autorización" do
      prime(permission_registry)
      bigger = Access::PermissionRegistry.new
      bigger.register("demo", permission_registry.definitions.to_h { |d| [ d.key, { description: d.description, roles: d.roles } ] }
        .merge("demo.cosa.nueva" => { description: "Nueva", roles: %w[org_owner] }))

      expect { sync_quietly(bigger) }.not_to raise_error
    end

    it "toma un candado consultivo de transacción (dos despliegues simultáneos no se pisan)" do
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { Access.sync!(permission_registry, allow_prune: true) }

      expect(statements).to include(a_string_matching(/pg_advisory_xact_lock/))
    end
  end

  describe "el registro global (lo que hacen los packs al arrancar)" do
    it "la base contiene exactamente los permisos registrados (salvo los módulos ficticios de la suite, que no viajan a la base compartida)" do
      expect(Access::Permission.pluck(:key).sort).to eq(AccessCatalogSuite.registry_without_samples.keys.sort)
    end
  end
end

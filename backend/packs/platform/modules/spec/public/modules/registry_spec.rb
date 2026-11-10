require "rails_helper"

# Criterio 1 de M0.09: un manifiesto inválido FALLA con un mensaje claro (al arrancar la app o en el test). El DSL implementa
# SOLO los campos de docs/architecture/05-module-system.md; todo lo demás es un error, no se ignora.
RSpec.describe Modules::Registry do
  subject(:manifests) { described_class.new }

  def define(key = :loyalty, **options, &block)
    block ||= proc { }
    manifests.define(key, **options) do
      name "Lealtad"
      version "1.0"
      instance_eval(&block)
    end
  end

  describe "un manifiesto válido" do
    let(:manifest) do
      define(:loyalty) do
        platform %i[customers notifications]
        permissions do
          permission "loyalty.card.read", description: "Ver tarjetas"
          permission "loyalty.card.manage", description: "Gestionar tarjetas"
        end
        role_grants do
          grant :company_manager, all: true
          grant :receptionist, %w[loyalty.card.read]
        end
        api_scopes "read:loyalty" => %w[loyalty.card.read], "write:loyalty" => %w[loyalty.card.manage]
        settings_schema(
          type: "object",
          properties: { points_per_visit: { type: "integer", minimum: 0, maximum: 1000, default: 10, "x-levels": %w[company] } }
        )
        settings_levels %i[company branch]
        publishes %w[platform.module_enabled.v1]
        navigation [ { key: "cards", path: "/loyalty", permission: "loyalty.card.read" } ]
        on_enable "Loyalty::Lifecycle::OnEnable"
        on_disable "Loyalty::Lifecycle::OnDisable"
      end
    end

    it "expone sus campos normalizados e inmutables" do
      expect(manifest).to have_attributes(
        key: "loyalty", name: "Lealtad", version: "1.0", requires: [], platform: %w[customers notifications],
        settings_levels: %w[company branch], on_enable: "Loyalty::Lifecycle::OnEnable", on_disable: "Loyalty::Lifecycle::OnDisable"
      )
      expect(manifest.permissions.map(&:key)).to eq(%w[loyalty.card.read loyalty.card.manage])
      expect(manifest).to be_frozen
    end

    it "expande `all: true` a todos los permisos del módulo" do
      expect(manifest.role_grants).to eq("company_manager" => %w[loyalty.card.read loyalty.card.manage], "receptionist" => %w[loyalty.card.read])
    end

    it "queda en el registro y se recupera por su key" do
      manifest

      expect(manifests.fetch("loyalty")).to equal(manifest)
      expect(manifests.fetch(:loyalty)).to equal(manifest)
      expect(manifests.keys).to eq(%w[loyalty])
    end

    it "resuelve la ruta del esquema de settings relativa al pack" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "settings.schema.json"), { type: "object", properties: { a: { type: "integer", minimum: 0, maximum: 9, default: 1 } } }.to_json)

        manifest = manifests.define(:ruta, root:) do
          name "Ruta"
          version "1.0"
          settings_schema "settings.schema.json"
        end

        expect(manifest.settings_schema.dig("properties", "a", "default")).to eq(1)
      end
    end

    it "sin esquema de settings no tiene settings" do
      expect(define(:vacio).settings_schema).to eq("type" => "object", "properties" => {}, "additionalProperties" => false)
    end
  end

  describe "validaciones (criterio 1)" do
    def expect_invalid(message, &block)
      expect { define(:loyalty, &block) }.to raise_error(Modules::InvalidManifest, message)
    end

    it "rechaza un permiso que no empieza por la key del módulo, con un mensaje que lo nombra" do
      expect_invalid(/loyalty.*"billing\.invoice\.read".*debe empezar por "loyalty\."/m) do
        permissions { permission "billing.invoice.read", description: "Ajeno" }
      end
    end

    it "rechaza un permiso con el formato <modulo>.<recurso>.<accion> roto" do
      expect_invalid(/"loyalty\.card".*<modulo>\.<recurso>\.<accion>/m) { permissions { permission "loyalty.card", description: "Corto" } }
    end

    it "rechaza un permiso sin descripción" do
      expect_invalid(/loyalty\.card\.read.*descripción/m) { permissions { permission "loyalty.card.read" } }
    end

    it "rechaza permisos repetidos" do
      expect_invalid(/repetido/) do
        permissions do
          permission "loyalty.card.read", description: "Uno"
          permission "loyalty.card.read", description: "Dos"
        end
      end
    end

    it "rechaza una key que no es snake_case o que es la de la plataforma" do
      expect { manifests.define(:"Mal-Nombre") { name("x") && version("1.0") } }.to raise_error(Modules::InvalidManifest, /snake_case/)
      expect { manifests.define(:platform) { name("x") && version("1.0") } }.to raise_error(Modules::InvalidManifest, /reservada/)
    end

    it "rechaza definir dos veces la misma key" do
      define(:loyalty)

      expect { define(:loyalty) }.to raise_error(Modules::InvalidManifest, /ya está definido/)
    end

    it "exige nombre y versión" do
      expect { manifests.define(:loyalty) { } }.to raise_error(Modules::InvalidManifest, /name.*version|version.*name/m)
    end

    it "rechaza una concesión a un rol que no es de sistema o a un permiso que el módulo no declara" do
      expect_invalid(/rol.*"jefe"/m) do
        permissions { permission "loyalty.card.read", description: "Ver" }
        role_grants { grant :jefe, all: true }
      end
      expect_invalid(/"loyalty\.card\.fantasma".*no declara/m) do
        permissions { permission "loyalty.card.read", description: "Ver" }
        role_grants { grant :receptionist, %w[loyalty.card.fantasma] }
      end
    end

    it "rechaza scopes de API mal nombrados o que apuntan a permisos que el módulo no declara" do
      expect_invalid(/"leer:loyalty".*read:loyalty/m) { api_scopes "leer:loyalty" => [] }
      expect_invalid(/"loyalty\.card\.fantasma"/) do
        permissions { permission "loyalty.card.read", description: "Ver" }
        api_scopes "read:loyalty" => %w[loyalty.card.fantasma]
      end
    end

    it "rechaza un evento publicado sin esquema registrado" do
      expect_invalid(/"loyalty\.card_issued\.v1".*esquema/m) { publishes %w[loyalty.card_issued.v1] }
    end

    it "rechaza navegación con un permiso que el módulo no declara o sin ruta" do
      expect_invalid(/navegación.*"loyalty\.card\.read"/m) { navigation [ { key: "cards", path: "/loyalty", permission: "loyalty.card.read" } ] }
      expect_invalid(/path/) do
        permissions { permission "loyalty.card.read", description: "Ver" }
        navigation [ { key: "cards", permission: "loyalty.card.read" } ]
      end
    end

    it "rechaza hooks que no son un nombre de constante" do
      expect_invalid(/on_enable.*"no es constante"/m) { on_enable "no es constante" }
    end

    it "rechaza un campo que el DSL no conoce (solo los campos de 05)" do
      expect_invalid(/campo desconocido.*color/m) { color "rojo" }
    end

    describe "esquema de settings" do
      it "rechaza un JSON Schema inválido" do
        expect_invalid(/settings.*JSON Schema válido/m) { settings_schema(type: "object", properties: { a: { type: "no-existe", default: 1 } }) }
      end

      it "rechaza una propiedad sin default (criterio de la tarea: settings sin default => error)" do
        expect_invalid(/"min_lead_time_minutes".*default/m) do
          settings_schema(type: "object", properties: { min_lead_time_minutes: { type: "integer" } })
        end
      end

      it "rechaza un default que no cumple su propio esquema" do
        expect_invalid(/"max_advance_days".*default.*no cumple/m) do
          settings_schema(type: "object", properties: { max_advance_days: { type: "integer", minimum: 1, maximum: 9, default: 0 } })
        end
      end

      it "EXIGE cotas: un entero sin minimum y maximum es un error (sonda P2b: 10**30)" do
        expect_invalid(/"a".*integer.*minimum.*maximum/m) { settings_schema(type: "object", properties: { a: { type: "integer", default: 1 } }) }
        expect_invalid(/"a".*maximum/m) { settings_schema(type: "object", properties: { a: { type: "number", minimum: 0, default: 1 } }) }
      end

      it "EXIGE cotas: una cadena libre sin maxLength es un error, salvo un enum o un const" do
        expect_invalid(/"a".*string.*maxLength/m) { settings_schema(type: "object", properties: { a: { type: "string", default: "" } }) }
        expect { define(:acotado) { settings_schema(type: "object", properties: { a: { type: "string", enum: %w[x y], default: "x" } }) } }.not_to raise_error
      end

      it "EXIGE cotas: un array sin maxItems es un error (sonda P3: 50 000 recordatorios) y también sus elementos" do
        expect_invalid(/"a".*array.*maxItems/m) { settings_schema(type: "object", properties: { a: { type: "array", items: { type: "boolean" }, default: [] } }) }
        expect_invalid(/"a\[\]\.n".*integer.*minimum.*maximum/m) do
          settings_schema(type: "object", properties: { a: { type: "array", maxItems: 3, default: [], items: { type: "object", properties: { n: { type: "integer" } } } } })
        end
      end

      it "los booleanos no necesitan cota" do
        expect { define(:boolean) { settings_schema(type: "object", properties: { a: { type: "boolean", default: true } }) } }.not_to raise_error
      end

      it "rechaza un esquema que no es un objeto con propiedades" do
        expect_invalid(/type.*object/m) { settings_schema(type: "array", items: { type: "string" }) }
      end

      it "rechaza un nivel desconocido o un x-levels fuera de settings_levels" do
        expect_invalid(/nivel.*"region"/m) { settings_levels %i[region] }
        expect_invalid(/"a".*x-levels.*branch/m) do
          settings_levels %i[company]
          settings_schema(type: "object", properties: { a: { type: "integer", default: 1, "x-levels": %w[branch] } })
        end
      end

      it "rechaza un archivo de esquema que no existe, nombrándolo" do
        expect_invalid(/no\/existe\.json/) { settings_schema "no/existe.json" }
      end
    end
  end

  describe "#validate! (reglas entre manifiestos)" do
    it "rechaza un requires que referencia un módulo inexistente" do
      define(:loyalty) { requires %i[fantasma] }

      expect { manifests.validate! }.to raise_error(Modules::InvalidManifest, /loyalty.*requires.*"fantasma"/m)
    end

    it "rechaza un requires cíclico, mostrando el ciclo" do
      define(:alfa) { requires %i[beta] }
      define(:beta) { requires %i[gamma] }
      define(:gamma) { requires %i[alfa] }

      expect { manifests.validate! }.to raise_error(Modules::InvalidManifest, /ciclo.*(alfa -> beta -> gamma -> alfa|beta -> gamma -> alfa -> beta|gamma -> alfa -> beta -> gamma)/m)
    end

    it "rechaza que un módulo se requiera a sí mismo" do
      expect { define(:loyalty) { requires %i[loyalty] } }.to raise_error(Modules::InvalidManifest, /a sí mismo/)
    end

    it "acepta una cadena de requires sin ciclos" do
      define(:alfa)
      define(:beta) { requires %i[alfa] }

      expect { manifests.validate! }.not_to raise_error
      expect(manifests.requirers_of("alfa").map(&:key)).to eq(%w[beta])
    end

    it "rechaza el mismo permiso declarado por dos módulos" do
      define(:alfa) { permissions { permission "alfa.x.read", description: "Uno" } }

      expect { define(:beta) { permissions { permission "alfa.x.read", description: "Dos" } } }.to raise_error(Modules::InvalidManifest, /beta.*alfa\.x\.read/m)
    end
  end

  describe "#fetch" do
    it "lanza Modules::UnknownModule con la key pedida" do
      expect { manifests.fetch("nada") }.to raise_error(Modules::UnknownModule, /nada/)
    end
  end
end

require "rails_helper"

RSpec.describe Events::Schemas do
  describe "catálogo de packs" do
    it "carga los esquemas de packs/*/*/app/public/*/events/*.json" do
      expect(described_class.names).to include("platform.organization_provisioned.v1")
    end

    it "cada archivo es un JSON Schema válido y su nombre de archivo es un nombre de evento válido" do
      files = Rails.root.glob("packs/*/*/app/public/*/events/*.json")

      expect(files).not_to be_empty
      files.each do |file|
        name = file.basename(".json").to_s
        expect(name).to match(Events::OutboxEvent::NAME_FORMAT)
        expect(JSONSchemer.valid_schema?(JSON.parse(file.read))).to be(true), "#{file} no es un JSON Schema válido"
      end
    end
  end

  describe ".register / .unregister" do
    it "registra un esquema en memoria y lo retira" do
      described_class.register("test.cosa.v1", { "type" => "object" })

      expect(described_class.names).to include("test.cosa.v1")

      described_class.unregister("test.cosa.v1")

      expect(described_class.names).not_to include("test.cosa.v1")
    end

    it "rechaza un esquema que no es un JSON Schema válido" do
      expect { described_class.register("test.mal.v1", { "type" => "nope" }) }.to raise_error(ArgumentError, /JSON Schema/)
    end
  end

  describe "catálogo con un archivo inválido" do
    after { described_class.reload! }

    it "falla al cargar con el nombre del archivo (valid_schema?), no al publicar" do
      Dir.mktmpdir do |dir|
        bad = Pathname(dir).join("test.malo.v1.json")
        bad.write('{ "type": "nope" }')
        allow(Rails.root).to receive(:glob).and_call_original
        allow(Rails.root).to receive(:glob).with(described_class::GLOB).and_return([ bad ])

        expect { described_class.reload! }.to raise_error(ArgumentError, /test\.malo\.v1\.json.*JSON Schema/)
      end
    end
  end

  describe ".definition" do
    it "devuelve el esquema crudo de un evento del catálogo" do
      expect(described_class.definition("platform.organization_provisioned.v1")).to include("required" => %w[organization_id company_id branch_id])
    end

    it "lanza UnknownEvent si no existe" do
      expect { described_class.definition("test.nada.v1") }.to raise_error(Events::UnknownEvent)
    end
  end

  describe ".validate!" do
    it "acepta un payload que cumple el esquema y devuelve el payload normalizado a JSON" do
      described_class.register("test.cosa.v1", EventSchemaHelpers::THING_HAPPENED)

      expect(described_class.validate!("test.cosa.v1", { thing_id: "a" })).to eq({ "thing_id" => "a" })
    ensure
      described_class.unregister("test.cosa.v1")
    end
  end
end

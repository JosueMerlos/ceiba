require "rails_helper"

RSpec.describe "Importadores del catálogo" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company, currency: "NIO") }

  describe Appointments::Imports::ServicesImporter do
    let(:importer) { described_class.new(company_id: company.id) }

    def cells(**overrides)
      { "nombre" => "Corte", "duracion_minutos" => "45", "precio" => "150", "moneda" => nil, "buffer_antes_minutos" => nil,
        "buffer_despues_minutos" => nil, "activo" => nil }.merge(overrides.transform_keys(&:to_s))
    end

    def validate(**overrides) = with_tenant(organization) { importer.validate(cells(**overrides)) }

    it "convierte el precio a unidades menores con la moneda de la empresa y valores por defecto" do
      expect(validate).to eq([ { name: "Corte", duration_minutes: 45, price_minor: 15_000, currency: "NIO", buffer_before_minutes: 0,
                                 buffer_after_minutes: 0, active: true }, {} ])
    end

    it "acepta punto o coma decimal con hasta dos decimales" do
      expect([ validate(precio: "150.50"), validate(precio: "150,5"), validate(precio: "0") ].map { it.first[:price_minor] }).to eq([ 15_050, 15_050, 0 ])
    end

    it "rechaza separadores de miles con un código propio, para no leer mal un monto" do
      expect([ validate(precio: "1.500,00"), validate(precio: "1,500.00"), validate(precio: "1.500") ].map(&:last))
        .to eq([ { "precio" => "thousands_separator" } ] * 3)
    end

    it "rechaza precios negativos, con más de dos decimales o que no son números" do
      expect([ validate(precio: "-5"), validate(precio: "10.5051"), validate(precio: "gratis"), validate(precio: nil) ].map(&:last))
        .to eq([ { "precio" => "invalid" }, { "precio" => "invalid" }, { "precio" => "invalid" }, { "precio" => "blank" } ])
    end

    it "rechaza una moneda distinta a la de la empresa y acepta la misma en minúsculas" do
      expect([ validate(moneda: "USD").last, validate(moneda: "nio").last ]).to eq([ { "moneda" => "currency_mismatch" }, {} ])
    end

    it "valida duración, búferes y el campo activo" do
      expect(validate(duracion_minutos: "0", buffer_antes_minutos: "x", activo: "quizá").last)
        .to eq("duracion_minutos" => "invalid", "buffer_antes_minutos" => "invalid", "activo" => "invalid")
      expect(validate(duracion_minutos: "1441").last).to eq("duracion_minutos" => "invalid")
      expect(validate(activo: "No").first[:active]).to be(false)
    end

    it "solo admite saltar duplicados" do
      expect(importer.duplicate_modes).to eq(%w[skip])
    end

    describe "#apply" do
      def apply(**overrides)
        with_tenant(organization) do
          attributes, errors = importer.validate(cells(**overrides))
          raise "invalid fixture: #{errors}" if errors.any?

          importer.apply(attributes, mode: "skip")
        end
      end

      it "crea el servicio auditado" do
        expect(apply).to eq(:created)
        expect(with_tenant(organization) { Appointments::Service.where(company_id: company.id).pluck(:name, :price_minor) }).to eq([ [ "Corte", 15_000 ] ])
        expect(with_tenant(organization) { Audit::Event.where(action: "service.created").count }).to eq(1)
      end

      it "omite uno con el mismo nombre normalizado y no cambia su precio" do
        existing = create_in(organization, :service, company:, name: "  corte ", price_minor: 9_900)

        expect(apply(nombre: "CORTE", precio: "500")).to eq(:skipped)
        expect(with_tenant(organization) { existing.reload.price_minor }).to eq(9_900)
      end

      it "crea uno con el nombre de un servicio archivado" do
        create_in(organization, :service, company:, name: "Corte", archived_at: 1.day.ago)

        expect(apply).to eq(:created)
      end

      it "omite el segundo con el mismo nombre dentro del mismo importador" do
        expect([ apply, apply(nombre: "corte") ]).to eq(%i[created skipped])
      end
    end
  end

  describe Appointments::Imports::ProfessionalsImporter do
    let(:importer) { described_class.new(company_id: company.id) }

    def validate(cells) = with_tenant(organization) { importer.validate(cells) }

    it "valida el nombre y el campo activo" do
      expect(validate("nombre" => "Rosa Martínez", "activo" => "si")).to eq([ { display_name: "Rosa Martínez", active: true }, {} ])
      expect(validate("nombre" => nil, "activo" => "tal vez").last).to eq("nombre" => "blank", "activo" => "invalid")
      expect(validate("nombre" => "r" * 121, "activo" => nil).last).to eq("nombre" => "too_long")
    end

    it "crea al profesional y omite a uno no archivado con el mismo nombre" do
      create_in(organization, :professional, company:, display_name: "Ana Gómez")

      outcomes = with_tenant(organization) do
        [ importer.apply({ display_name: "Rosa Martínez", active: true }, mode: "skip"), importer.apply({ display_name: "ana gómez", active: true }, mode: "skip") ]
      end

      expect(outcomes).to eq(%i[created skipped])
    end
  end
end

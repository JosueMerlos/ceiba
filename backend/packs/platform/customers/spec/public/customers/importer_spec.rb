require "rails_helper"

RSpec.describe Customers::Importer do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:importer) { described_class.new(company_id: company.id) }

  def cells(**overrides) = { "nombre" => "Ana López", "telefono" => "8800 0101", "correo" => nil, "notas" => nil }.merge(overrides.transform_keys(&:to_s))

  def validate(**overrides) = with_tenant(organization) { importer.validate(cells(**overrides)) }

  describe "#validate" do
    it "normaliza el teléfono a E.164 con la región de la organización y no devuelve errores" do
      attributes, errors = validate(correo: " Ana@Ejemplo.com ")

      expect([ attributes, errors ]).to eq([ { full_name: "Ana López", phone_e164: "+50588000101", email: "ana@ejemplo.com", notes: nil }, {} ])
    end

    it "señala un teléfono inválido con su columna y un código, nunca con el valor" do
      expect(validate(telefono: "12").last).to eq("telefono" => "invalid")
    end

    it "rechaza la notación científica en que Excel convierte un número largo" do
      expect(validate(telefono: "5.05888E+10").last).to eq("telefono" => "invalid")
    end

    it "señala los obligatorios vacíos y el correo mal formado a la vez" do
      expect(validate(nombre: nil, telefono: nil, correo: "no-es-correo").last).to eq("nombre" => "blank", "telefono" => "blank", "correo" => "invalid")
    end

    it "señala los textos que superan el largo del modelo" do
      expect(validate(nombre: "a" * 201, notas: "n" * 2001).last).to eq("nombre" => "too_long", "notas" => "too_long")
    end

    it "usa el teléfono normalizado como clave de duplicado dentro del archivo" do
      first, = validate(telefono: "8800 0101")
      second, = validate(telefono: "+505 8800-0101")

      expect(importer.duplicate_key(first)).to eq(importer.duplicate_key(second))
    end
  end

  describe "#warnings" do
    it "avisa que el consentimiento declarado en el archivo no se registra" do
      expect(importer.warnings(%w[nombre telefono consentimiento_recordatorios fuente_consentimiento])).to eq([ "consent_not_recorded" ])
    end

    it "no avisa nada sin esas columnas" do
      expect(importer.warnings(%w[nombre telefono])).to eq([])
    end
  end

  describe "#apply" do
    def apply(mode:, **overrides)
      with_tenant(organization) do
        attributes, errors = importer.validate(cells(**overrides))
        raise "invalid fixture: #{errors}" if errors.any?

        importer.apply(attributes, mode:)
      end
    end

    def customers = with_tenant(organization) { Customers::Customer.where(company_id: company.id).order(:created_at).to_a }

    it "crea al cliente nuevo y lo audita por id" do
      expect(apply(mode: "skip", notas: "Prefiere la mañana")).to eq(:created)

      customer = customers.sole
      expect([ customer.full_name, customer.phone_e164, customer.notes ]).to eq([ "Ana López", "+50588000101", "Prefiere la mañana" ])
      expect(with_tenant(organization) { Audit::Event.where(action: "customer.created", auditable_id: customer.id).count }).to eq(1)
    end

    context "con un cliente activo del mismo teléfono" do
      let!(:existing) { create_in(organization, :customer, company:, full_name: "Ana Vieja", phone_e164: "+50588000101", email: "vieja@ejemplo.com") }

      it "saltar no lo modifica" do
        expect(apply(mode: "skip", nombre: "Otra Persona", correo: "nueva@ejemplo.com")).to eq(:skipped)
        expect(with_tenant(organization) { existing.reload.attributes.slice("full_name", "email") }).to eq("full_name" => "Ana Vieja", "email" => "vieja@ejemplo.com")
      end

      it "actualizar cambia lo que trae la fila y una celda vacía no borra el dato" do
        expect(apply(mode: "update", nombre: "Ana Nueva", correo: nil, notas: "Nueva nota")).to eq(:updated)
        expect(with_tenant(organization) { existing.reload.attributes.slice("full_name", "email", "notes") })
          .to eq("full_name" => "Ana Nueva", "email" => "vieja@ejemplo.com", "notes" => "Nueva nota")
      end

      it "actualizar sin cambios cuenta como omitido" do
        expect(apply(mode: "update", nombre: "Ana Vieja")).to eq(:skipped)
      end
    end

    context "con un cliente archivado del mismo teléfono" do
      let!(:archived) do
        create_in(organization, :customer, company:, phone_e164: "+50588000101", email: "previa@ejemplo.com", notes: "Nota previa", archived_at: 1.day.ago)
      end

      it "saltar no lo toca y queda archivado" do
        expect(apply(mode: "skip", nombre: "Ana Nueva")).to eq(:skipped)
        expect(with_tenant(organization) { archived.reload.attributes.slice("archived_at", "email", "notes").values.compact.size }).to eq(3)
      end

      it "actualizar lo restaura con los datos de la fila y limpia lo que la fila no trae" do
        expect(apply(mode: "update", nombre: "Ana Nueva", correo: nil, notas: nil)).to eq(:restored)
        expect(with_tenant(organization) { archived.reload.attributes.slice("full_name", "archived_at", "email", "notes") })
          .to eq("full_name" => "Ana Nueva", "archived_at" => nil, "email" => nil, "notes" => nil)
      end
    end

    it "el mismo teléfono en otra empresa es otro cliente" do
      other = create_in(organization, :company)
      create_in(organization, :customer, company: other, phone_e164: "+50588000101")

      expect(apply(mode: "skip")).to eq(:created)
    end
  end
end

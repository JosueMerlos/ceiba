require "rails_helper"

RSpec.describe Customers::Customer do
  let(:organization) { create(:organization) }
  let(:company_a) { create_in(organization, :company) }
  let(:company_b) { create_in(organization, :company) }

  def raw_value(customer, column)
    ApplicationRecord.connection.select_value("SELECT #{column} FROM customers WHERE id = #{ApplicationRecord.connection.quote(customer.id)}")
  end

  describe "teléfono" do
    it "normaliza el número local a E.164 con el país de la organización" do
      with_tenant(organization) do
        customer = create(:customer, company: company_a, phone_e164: "8888-7777")

        expect(customer.reload.phone_e164).to eq("+50588887777")
      end
    end

    it "con un teléfono inválido es inválido (phone_e164: invalid)" do
      with_tenant(organization) do
        customer = build(:customer, company: company_a, phone_e164: "123")

        expect(customer).not_to be_valid
        expect(customer.errors.where(:phone_e164).map(&:type)).to eq([ :invalid ])
      end
    end

    it "un número con forma de E.164 que no es un número real es inválido y no se guarda sin normalizar", :aggregate_failures do
      with_tenant(organization) do
        %w[+50511111111 +15550000000 +1234567].each do |fake|
          customer = build(:customer, company: company_a, phone_e164: fake)

          expect(customer).not_to be_valid, "#{fake} debería ser inválido"
          expect(customer.errors.where(:phone_e164).map(&:type)).to eq([ :invalid ])
        end
      end
    end

    it "el mismo teléfono dos veces en la misma empresa es inválido (phone_e164: taken)" do
      with_tenant(organization) do
        create(:customer, company: company_a, phone_e164: "8888-7777")
        duplicate = build(:customer, company: company_a, phone_e164: "+505 8888 7777")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:phone_e164).map(&:type)).to eq([ :taken ])
      end
    end

    it "el mismo teléfono en dos empresas del mismo grupo son dos clientes distintos e invisibles entre sí" do
      with_tenant(organization) do
        in_a = create(:customer, company: company_a, phone_e164: "8888-7777")
        in_b = create(:customer, company: company_b, phone_e164: "8888-7777")

        expect(in_a.id).not_to eq(in_b.id)
        expect(described_class.where(company_id: company_a.id).pluck(:id)).to eq([ in_a.id ])
        expect(described_class.where(company_id: company_b.id).pluck(:id)).to eq([ in_b.id ])
      end
    end

    it "buscar por teléfono con otro formato encuentra al cliente de la empresa" do
      with_tenant(organization) do
        customer = create(:customer, company: company_a, phone_e164: "8888-7777")
        create(:customer, company: company_b, phone_e164: "8888-7777")

        found = described_class.where(company_id: company_a.id).with_phone("8888 7777")

        expect(found.pluck(:id)).to eq([ customer.id ])
        expect(described_class.with_phone("no es un teléfono")).to be_empty
      end
    end
  end

  describe "teléfono ya guardado que dejó de validar" do
    # Created while the number is valid, then phonelib "forgets" it.
    let!(:customer) { with_tenant(organization) { create(:customer, company: company_a, phone_e164: "8888-7777") } }

    before { allow(Customers::Phone).to receive(:normalize).and_return(nil) }

    it "se puede archivar y actualizar las notas sin revalidar el teléfono", :aggregate_failures do
      with_tenant(organization) do
        Customers::Archive.call(customer: customer)
        customer.reload.update!(notes: "llamar por la tarde")

        expect(customer.reload).to have_attributes(archived_at: be_present, notes: "llamar por la tarde", phone_e164: "+50588887777")
      end
    end

    it "cambiar el teléfono a uno inválido sigue siendo rechazado" do
      with_tenant(organization) do
        customer.phone_e164 = "+50511111111"

        expect(customer).not_to be_valid
        expect(customer.errors.where(:phone_e164).map(&:type)).to eq([ :invalid ])
      end
    end
  end

  describe "cifrado" do
    it "teléfono, correo y notas no aparecen en claro en la tabla" do
      with_tenant(organization) do
        customer = create(:customer, company: company_a, phone_e164: "8888-7777", email: "Ana@Example.com", notes: "alérgica al níquel")

        raw = %w[phone_e164 email notes].map { |column| raw_value(customer, column) }

        expect(raw).to all(be_present)
        expect(raw.join).not_to match(/50588887777|8888|ana@example|alérgica|níquel/i)
        expect(customer.reload.attributes.slice("phone_e164", "email", "notes")).to eq(
          "phone_e164" => "+50588887777", "email" => "ana@example.com", "notes" => "alérgica al níquel"
        )
      end
    end

    it "el correo es buscable sin importar las mayúsculas" do
      with_tenant(organization) do
        customer = create(:customer, company: company_a, email: "Ana@Example.com")

        expect(described_class.where(email: "ANA@example.COM").pluck(:id)).to eq([ customer.id ])
      end
    end
  end

  describe "nombre" do
    it "sin nombre o solo con espacios es inválido" do
      with_tenant(organization) do
        expect([ "", "   " ].map { |name| build(:customer, company: company_a, full_name: name).valid? }).to all(be(false))
      end
    end

    it "name_prefix busca por prefijo sin distinguir mayúsculas" do
      with_tenant(organization) do
        ana = create(:customer, company: company_a, full_name: "Ana López")
        create(:customer, company: company_a, full_name: "Bruno Ana")

        expect(described_class.name_prefix("ANA").pluck(:id)).to eq([ ana.id ])
      end
    end

    it "name_prefix escapa los comodines de LIKE" do
      with_tenant(organization) do
        create(:customer, company: company_a, full_name: "Ana")
        percent = create(:customer, company: company_a, full_name: "100% Fiel")

        expect(described_class.name_prefix("%")).to be_empty
        expect(described_class.name_prefix("_")).to be_empty
        expect(described_class.name_prefix("100%").pluck(:id)).to eq([ percent.id ])
      end
    end
  end

  describe "archivado" do
    it "active excluye a los archivados" do
      with_tenant(organization) do
        active = create(:customer, company: company_a)
        create(:customer, company: company_a, archived_at: Time.current)

        expect(described_class.active.pluck(:id)).to eq([ active.id ])
      end
    end
  end
end

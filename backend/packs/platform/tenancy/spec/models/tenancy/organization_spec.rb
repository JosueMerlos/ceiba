require "rails_helper"

RSpec.describe Tenancy::Organization do
  subject(:organization) { described_class.new(name: "Barbería El Güegüense") }

  it "usa la tabla organizations" do
    expect(described_class.table_name).to eq("organizations")
  end

  it "es válida con solo el nombre" do
    expect(organization).to be_valid
  end

  it "usa NI como país por defecto" do
    expect(organization.country_code).to eq("NI")
  end

  it "nace activa" do
    expect(organization).to be_active
  end

  it "exige nombre" do
    organization.name = " "

    expect(organization).not_to be_valid
    expect(organization.errors[:name]).to be_present
  end

  it "acepta una razón social opcional" do
    organization.legal_name = "Barbería El Güegüense, S.A."

    expect(organization).to be_valid
  end

  it "exige un código de país ISO 3166-1 alfa-2 en mayúsculas" do
    %w[ni N NIC 1A].each do |code|
      organization.country_code = code

      expect(organization).not_to be_valid, "#{code} debería ser inválido"
    end
  end

  it "rechaza un estado desconocido" do
    organization.status = "banned"

    expect(organization).not_to be_valid
  end

  it "permite suspenderla" do
    organization.status = "suspended"

    expect(organization).to be_valid
  end

  it "es la raíz del tenant: no tiene organization_id" do
    expect(described_class.column_names).not_to include("organization_id")
  end

  it "se puede consultar sin tenant activo (no es una tabla tenant)" do
    expect { described_class.count }.not_to raise_error
  end

  it "guarda el id como UUID generado por la base" do
    organization.save!

    expect(organization.id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "la base rechaza un estado inválido aunque se salte la validación" do
    organization.status = "banned"

    expect { organization.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /chk_organizations_status/)
  end
end

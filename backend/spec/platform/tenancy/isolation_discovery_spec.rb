require "rails_helper"

# Criterio 4 de M0.05: un modelo tenant nuevo, en cualquier pack, SIN factory hace fallar la suite de aislamiento
# indicando qué factory falta. Se demuestra con una tabla tenant real (efímera) y un modelo sin factory.
RSpec.describe TenantIsolation do
  let(:probe_table) { "isolation_probes" }
  let(:probe_model) do
    Class.new(ApplicationRecord) do
      self.table_name = "isolation_probes"
      acts_as_tenant :organization, class_name: "Tenancy::Organization"
    end
  end

  around do |example|
    OwnerConnection.with do |owner|
      owner.drop_table(probe_table, if_exists: true)
      owner.create_tenant_table(probe_table) { |t| t.string :label }
      stub_const("IsolationProbe", probe_model)
      example.run
    ensure
      owner.drop_table(probe_table, if_exists: true)
    end
  end

  it "descubre el modelo por su columna organization_id, sin listas manuales" do
    expect(described_class.models([ probe_model, Tenancy::Organization, ApplicationRecord ])).to eq([ probe_model ])
  end

  it "no descubre modelos anónimos que no se pueden nombrar" do
    anonymous = Class.new(ApplicationRecord) { self.table_name = "isolation_probes" }

    expect(described_class.models([ anonymous ])).to be_empty
  end

  it "detecta el modelo sin factory (criterio 4)" do
    expect(described_class.missing_factories(described_class.models([ probe_model, Tenancy::Company ]))).to eq([ probe_model ])
  end

  it "falla con un mensaje explícito que dice qué factory agregar" do
    expect { described_class.factory_for!(probe_model) }
      .to raise_error(TenantIsolation::MissingFactory, /Falta una factory para IsolationProbe.*isolation_probes.*factory :isolation_probe, class: "IsolationProbe"/m)
  end

  it "encuentra la factory de un modelo que sí la tiene" do
    expect(described_class.factory_for!(Tenancy::Branch).name).to eq(:branch)
  end

  it "señala las tablas tenant sin modelo" do
    expect(described_class.uncovered_tables(described_class.models([ Tenancy::Company ]))).to include(probe_table, "branches")
  end
end

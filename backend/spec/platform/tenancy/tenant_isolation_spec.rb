require "rails_helper"

# A new tenant model, in any pack, WITHOUT a factory fails the isolation suite saying which factory is missing. Shown
# with a real (ephemeral) tenant table and a model without a factory.
RSpec.describe TenantIsolation do
  let(:probe_table) { "isolation_probes" }
  let(:probe_model) do
    Class.new(ApplicationRecord) do
      self.table_name = "isolation_probes"
      acts_as_tenant :organization, class_name: "Tenancy::Organization"
    end
  end

  # The table is real (ephemeral, created by the owner): a "new" tenant model without a factory.
  before do
    OwnerConnection.with do |owner|
      owner.drop_table(probe_table, if_exists: true)
      owner.create_tenant_table(probe_table) { |t| t.string :label }
    end
    stub_const("IsolationProbe", probe_model)
  end

  after { OwnerConnection.with { |owner| owner.drop_table(probe_table, if_exists: true) } }

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

  it "la propia suite de aislamiento FALLA para el modelo sin factory, con el mensaje explícito (criterio 4)" do
    group = RSpec.describe("IsolationProbe") { it_behaves_like "un modelo tenant aislado", IsolationProbe }
    group.run(RSpec::Core::NullReporter)
    failures = group.descendants.flat_map(&:examples).filter_map { |example| example.execution_result.exception }

    expect(failures.size).to eq(15) # all except those that need no records (NoTenantSet, guard included, update_all, on_duplicate)
    expect(failures.map(&:message)).to all(include("Falta una factory para IsolationProbe"))
  ensure
    RSpec.world.example_groups.delete(group)
  end

  describe ".association_violations" do
    let(:root) do
      Class.new(ApplicationRecord) do
        self.table_name = "organizations"
        def self.name = "RootProbe"
        has_many :probes, class_name: "IsolationProbe", foreign_key: :organization_id
      end
    end
    let(:sibling) do
      Class.new(ApplicationRecord) do
        self.table_name = "isolation_probes"
        def self.name = "SiblingProbe"
        acts_as_tenant :organization, class_name: "Tenancy::Organization"
        has_many :others, class_name: "IsolationProbe", foreign_key: :organization_id
      end
    end

    before { stub_const("RootProbe", root) && stub_const("SiblingProbe", sibling) }

    it "marca una asociación desde un modelo raíz hacia un modelo tenant" do
      expect(described_class.association_violations([ root ])).to contain_exactly(a_string_matching(/RootProbe\.has_many :probes -> IsolationProbe.*cruzaría tenants/))
    end

    it "marca una asociación hacia un modelo tenant con foreign_key organization_id" do
      expect(described_class.association_violations([ sibling ])).to contain_exactly(a_string_matching(/SiblingProbe\.has_many :others/))
    end

    it "no marca belongs_to :organization ni las asociaciones entre tenant por la clave del padre" do
      expect(described_class.association_violations([ Tenancy::Branch, Tenancy::Company ])).to be_empty
    end
  end

  it "encuentra la factory de un modelo que sí la tiene" do
    expect(described_class.factory_for!(Tenancy::Branch).name).to eq(:branch)
  end

  it "señala las tablas tenant sin modelo" do
    expect(described_class.uncovered_tables(described_class.models([ Tenancy::Company ]))).to include(probe_table, "branches")
  end
end

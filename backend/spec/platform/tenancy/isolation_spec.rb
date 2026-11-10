require "rails_helper"

# Tenant isolation suite. Discovers the models with organization_id and, for EACH one, proves that organization A never
# sees B's data. A new model in any pack gets in on its own; without a factory the test FAILS (it is not skipped).
# Authorization between companies of the same organization is another suite.
RSpec.describe "Aislamiento de tenant" do
  it "descubre al menos los modelos tenant de tenancy" do
    expect(TenantIsolation.models).to include(Tenancy::Company, Tenancy::Branch)
  end

  it "cubre todas las tablas tenant: cada una tiene un modelo (o una exención justificada)" do
    expect(TenantIsolation.uncovered_tables(TenantIsolation.models)).to be_empty
  end

  it "ninguna asociación de ningún modelo cruza tenants (guardián de asociaciones)" do
    expect(TenantIsolation.association_violations).to be_empty
  end

  it "una organización cargada en el contexto A no ofrece acceso a las empresas de B" do
    expect(Tenancy::Organization.new).not_to respond_to(:companies)
  end

  TenantIsolation.models.each do |model|
    describe model.name do
      it_behaves_like "un modelo tenant aislado", model
    end
  end
end

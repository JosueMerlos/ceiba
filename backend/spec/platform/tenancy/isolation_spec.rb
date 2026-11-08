require "rails_helper"

# Suite de aislamiento de tenant (M0.05). Descubre los modelos con organization_id y, para CADA uno, demuestra que
# la organización A nunca ve datos de la B. Un modelo nuevo de cualquier pack entra solo; si no tiene factory, el
# test FALLA (no se salta). La autorización entre empresas de una misma organización es otra suite (M0.08).
RSpec.describe "Aislamiento de tenant" do
  it "descubre al menos los modelos tenant de tenancy" do
    expect(TenantIsolation.models).to include(Tenancy::Company, Tenancy::Branch)
  end

  it "cubre todas las tablas tenant: cada una tiene un modelo (o una exención justificada)" do
    expect(TenantIsolation.uncovered_tables(TenantIsolation.models)).to be_empty
  end

  TenantIsolation.models.each do |model|
    describe model.name do
      it_behaves_like "un modelo tenant aislado", model
    end
  end
end

require "rails_helper"

# Suite de aislamiento de tenant (M0.05). Descubre los modelos con organization_id y, para CADA uno, demuestra que
# la organización A nunca ve datos de la B. Un modelo nuevo de cualquier pack entra solo; si no tiene factory, el
# test FALLA (no se salta). La autorización entre empresas de una misma organización es otra suite (M0.08).
RSpec.describe "Aislamiento de tenant" do
  tenant_models = TenantIsolation.models

  it "descubre al menos los modelos tenant de tenancy" do
    expect(tenant_models).to include(Tenancy::Company, Tenancy::Branch)
  end

  it "cubre todas las tablas tenant: cada una tiene un modelo (o una exención justificada)" do
    expect(TenantIsolation.uncovered_tables(tenant_models)).to be_empty
  end

  tenant_models.each do |model|
    describe model.name do
      let(:factory) { TenantIsolation.factory_for!(model).name }
      let(:organization_a) { create(:organization) }
      let(:organization_b) { create(:organization) }
      let!(:record_a) { create_in(organization_a, factory) }
      let!(:record_b) { create_in(organization_b, factory) }

      it "tiene una factory" do
        expect { TenantIsolation.factory_for!(model) }.not_to raise_error
      end

      it "sin tenant activo lanza NoTenantSet" do
        expect { model.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
        expect { model.to_a }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
      end

      it "con el tenant A, count y las consultas no incluyen registros de B" do
        with_tenant(organization_a) do
          expect(model.pluck(:organization_id).uniq).to eq([ organization_a.id ])
          expect(model.where(id: record_b.id)).to be_empty
          expect(model.exists?(record_a.id)).to be(true)
        end
      end

      it "con el tenant A, un find de un id de B lanza RecordNotFound" do
        with_tenant(organization_a) do
          expect { model.find(record_b.id) }.to raise_error(ActiveRecord::RecordNotFound)
          expect(model.find_by(id: record_b.id)).to be_nil
        end
      end

      it "con el tenant B ocurre lo mismo a la inversa" do
        with_tenant(organization_b) do
          expect { model.find(record_a.id) }.to raise_error(ActiveRecord::RecordNotFound)
          expect(model.count).to eq(model.where(organization_id: organization_b.id).count)
        end
      end
    end
  end
end

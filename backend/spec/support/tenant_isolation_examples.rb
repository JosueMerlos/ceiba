# Las comprobaciones que TODO modelo tenant debe pasar. La suite de aislamiento (spec/platform/tenancy/isolation_spec.rb)
# las ejecuta para cada modelo descubierto. Requiere que el modelo tenga factory (si no, FALLAN, no se saltan).
RSpec.shared_examples "un modelo tenant aislado" do |model|
  let(:factory) { TenantIsolation.factory_for!(model).name }
  let(:organization_a) { create(:organization) }
  let(:organization_b) { create(:organization) }
  let(:record_a) { create_in(organization_a, factory) }
  let(:record_b) { create_in(organization_b, factory) }

  it "tiene una factory" do
    expect { TenantIsolation.factory_for!(model) }.not_to raise_error
  end

  it "sin tenant activo lanza NoTenantSet" do
    expect { model.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    expect { model.all.to_a }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
  end

  it "con el tenant A, count y las consultas no incluyen registros de B" do
    ids = [ record_a.id, record_b.id ]

    with_tenant(organization_a) do
      expect(model.where(id: ids).pluck(:id)).to eq([ record_a.id ])
      expect(model.pluck(:organization_id).uniq).to eq([ organization_a.id ])
      expect(model.count).to eq(model.where(organization_id: organization_a.id).count)
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
      expect(model.exists?(record_b.id)).to be(true)
    end
  end
end

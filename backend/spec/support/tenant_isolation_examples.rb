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

  # Escrituras: la barrera 1 no puede ser solo de lectura. Se cierra en el modelo (Tenancy::TenantWriteGuard) y, más
  # adelante, en la base con RLS (M4.03).
  it "incluye el guard de escritura de tenant" do
    expect(model).to include(Tenancy::TenantWriteGuard)
  end

  it "con el tenant A, crear un registro con organization_id de B se rechaza incluso saltándose las validaciones" do
    with_tenant(organization_a) do
      record = build(factory)
      record.organization_id = organization_b.id

      expect { record.save!(validate: false) }.to raise_error(Tenancy::TenantMismatch)
    end
  end

  it "con el tenant A, mover un registro propio a la organización B lanza TenantIsImmutable" do
    record = record_a

    with_tenant(organization_a) do
      loaded = model.find(record.id)
      loaded.organization_id = organization_b.id

      expect { loaded.save!(validate: false) }.to raise_error(Tenancy::TenantIsImmutable)
    end
  end

  it "con el tenant A, destruir un registro cuyo organization_id no es el del tenant se rechaza" do
    with_tenant(organization_a) do
      loaded = model.find(record_a.id)
      loaded.organization_id = organization_b.id

      expect { loaded.destroy }.to raise_error(Tenancy::TenantMismatch)
    end
  end
end

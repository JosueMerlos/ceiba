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

  # Tablas append-only (audit_events): el UPDATE/DELETE de cualquier fila lo rechaza el trigger; no hay nada que aislar.
  append_only = TenantIsolation.append_only?(model)

  it "con el tenant A, mover un registro propio a la organización B lanza TenantIsImmutable", unless: append_only do
    record = record_a

    with_tenant(organization_a) do
      loaded = model.find(record.id)
      loaded[:organization_id] = organization_b.id # el writer lo frena acts_as_tenant; write_attribute no pasa por él

      expect { loaded.save!(validate: false) }.to raise_error(Tenancy::TenantIsImmutable)
    end
  end

  def unique_by_tenant = %i[organization_id id]

  # Escrituras masivas: upsert_all con el id de un registro de B desde A lo sobrescribiría y lo movería a A.
  describe "escrituras masivas" do
    def row_of_b = record_b.attributes

    it "upsert_all sin unique_by sobre un índice con organization_id se rechaza (ArgumentError)" do
      with_tenant(organization_a) do
        expect { model.upsert_all([ row_of_b ], unique_by: :id) }.to raise_error(ArgumentError, /organization_id/)
      end
    end

    it "upsert_all con la fila de B desde A se rechaza (TenantMismatch) y B queda intacto" do
      with_tenant(organization_a) do
        expect { model.upsert_all([ row_of_b ], unique_by: unique_by_tenant) }.to raise_error(Tenancy::TenantMismatch)
      end
      with_tenant(organization_b) { expect(model.find(record_b.id).organization_id).to eq(organization_b.id) }
    end

    it "insert_all e insert_all! con la fila de B desde A se rechazan" do
      with_tenant(organization_a) do
        expect { model.insert_all([ row_of_b ]) }.to raise_error(Tenancy::TenantMismatch)
        expect { model.insert_all!([ row_of_b ]) }.to raise_error(Tenancy::TenantMismatch)
      end
    end

    it "upsert_all de una fila propia con unique_by (organization_id, id) sigue permitido", unless: append_only do
      own = record_a.attributes

      with_tenant(organization_a) do
        expect { model.upsert_all([ own ], unique_by: unique_by_tenant) }.not_to raise_error
      end
    end

    it "update_columns con organization_id lanza TenantIsImmutable" do
      record = record_a

      with_tenant(organization_a) do
        expect { model.find(record.id).update_columns(organization_id: organization_b.id) }.to raise_error(Tenancy::TenantIsImmutable)
      end
    end

    it "update_all con organization_id lanza TenantIsImmutable" do
      with_tenant(organization_a) do
        expect { model.update_all(organization_id: organization_b.id) }.to raise_error(Tenancy::TenantIsImmutable)
      end
    end
  end

  # Un objeto de B que sigue en memoria (cargado en el contexto B) NO se puede escribir ni borrar desde el contexto A:
  # el UPDATE/DELETE va por clave primaria, sin default scope, así que lo cierra el guard.
  describe "objetos de otra organización en memoria" do
    define_method(:target) { model }

    def stale_b = with_tenant(organization_b) { target.find(record_b.id) }

    def b_untouched?(before)
      with_tenant(organization_b) { target.find(record_b.id).updated_at == before }
    end

    it "update_attribute, touch y update_columns desde A se rechazan y la fila de B queda intacta", unless: append_only do
      before = record_b.updated_at
      stale = stale_b

      with_tenant(organization_a) do
        [ -> { stale.update_attribute(:updated_at, 1.day.from_now) }, -> { stale.touch }, -> { stale.update_columns(updated_at: 2.days.from_now) } ].each do |attempt|
          expect(&attempt).to raise_error(Tenancy::TenantMismatch)
        end
      end
      expect(b_untouched?(before)).to be(true)
    end

    it "delete y destroy desde A se rechazan y la fila de B sigue existiendo", unless: append_only do
      before = record_b.updated_at
      stale = stale_b

      with_tenant(organization_a) do
        expect { stale.delete }.to raise_error(Tenancy::TenantMismatch)
        expect { stale.destroy }.to raise_error(Tenancy::TenantMismatch)
      end
      expect(b_untouched?(before)).to be(true)
    end

    it "las sentencias llevan organization_id en las condiciones (defensa en profundidad)", unless: append_only do
      before = record_b.updated_at

      with_tenant(organization_a) do
        affected = model._update_record({ "updated_at" => 1.day.from_now }, { "id" => record_b.id })
        deleted = model._delete_record({ "id" => record_b.id })

        expect([ affected, deleted ]).to eq([ 0, 0 ])
      end
      expect(b_untouched?(before)).to be(true)
    end

    it "upsert_all con un on_duplicate propio que menciona organization_id se rechaza" do
      with_tenant(organization_a) do
        expect { model.upsert_all([ record_a.attributes ], unique_by: unique_by_tenant, on_duplicate: Arel.sql("organization_id = excluded.organization_id")) }
          .to raise_error(ArgumentError, /on_duplicate/)
      end
    end
  end
end

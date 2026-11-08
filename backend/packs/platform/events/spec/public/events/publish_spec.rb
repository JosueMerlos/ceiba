require "rails_helper"

# Events.publish solo INSERTA en el outbox, dentro de la transacción del caso de uso (ADR-0009).
# Sin fixtures transaccionales: el rollback y la ausencia de transacción deben ser reales.
RSpec.describe Events, ".publish" do
  self.use_transactional_tests = false

  let!(:organization) { Tenancy::Organization.create!(name: "Publicadora") }
  let(:event_name) { "test.thing_happened.v1" }

  before { register_event_schema(event_name) }

  after do
    with_tenant(organization) { Events::OutboxEvent.delete_all }
    Tenancy::Organization.where(id: organization.id).delete_all
  end

  def stored_events = with_tenant(organization) { Events::OutboxEvent.order(:id).to_a }

  describe "dentro de una transacción" do
    it "inserta una fila con el nombre, el payload y la organización del contexto (criterio: dentro -> fila)" do
      Tenancy.with_context(organization:) { described_class.publish(event_name, { thing_id: "t-1", size: 3 }) }

      expect(stored_events).to contain_exactly(
        have_attributes(name: event_name, payload: { "thing_id" => "t-1", "size" => 3 }, organization_id: organization.id, published_at: nil, attempts: 0)
      )
    end

    it "devuelve el evento publicado, con su id y su instante" do
      event = Tenancy.with_context(organization:) { described_class.publish(event_name, { thing_id: "t-1" }) }

      expect(event).to have_attributes(id: stored_events.first.id, name: event_name, organization_id: organization.id)
      expect(event.occurred_at).to be_within(5.seconds).of(Time.current)
    end

    it "guarda en metadata la empresa y la sucursal del contexto" do
      company = create_in(organization, :company)
      branch = create_in(organization, :branch, company:)

      Tenancy.with_context(organization:, company:, branch:) { described_class.publish(event_name, { thing_id: "t-1" }) }

      expect(stored_events.first.metadata).to include("company_id" => company.id, "branch_id" => branch.id)
    end

    it "mezcla metadata adicional del llamador sin pisar la del contexto" do
      Tenancy.with_context(organization:) { described_class.publish(event_name, { thing_id: "t-1" }, metadata: { request_id: "req-9" }) }

      expect(stored_events.first.metadata).to include("request_id" => "req-9")
    end

    it "NO encola nada en Sidekiq: publicar solo inserta (el relay publica después del commit)" do
      Sidekiq::Testing.fake! do
        Sidekiq::Queues.clear_all
        Tenancy.with_context(organization:) { described_class.publish(event_name, { thing_id: "t-1" }) }

        expect(Sidekiq::Queues.jobs_by_queue.values.flatten.map { |job| job["class"] }).not_to include("Events::DeliverJob")
      end
    end
  end

  describe "rollback (criterio 1)" do
    it "si el caso de uso falla después de publicar, no hay fila en outbox_events" do
      expect do
        Tenancy.with_context(organization:) do
          described_class.publish(event_name, { thing_id: "t-1" })
          raise "el caso de uso falla"
        end
      end.to raise_error("el caso de uso falla")

      expect(stored_events).to be_empty
    end

    it "un savepoint revertido descarta solo el evento de ese tramo" do
      Tenancy.with_context(organization:) do
        described_class.publish(event_name, { thing_id: "queda" })
        ApplicationRecord.transaction(requires_new: true) do
          described_class.publish(event_name, { thing_id: "se-va" })
          raise ActiveRecord::Rollback
        end
      end

      expect(stored_events.map { |event| event.payload["thing_id"] }).to eq([ "queda" ])
    end
  end

  describe "fuera de una transacción" do
    it "lanza Events::NotInTransaction y no escribe nada" do
      ActsAsTenant.with_tenant(organization) do
        expect { described_class.publish(event_name, { thing_id: "t-1" }) }.to raise_error(Events::NotInTransaction)
      end

      expect(stored_events).to be_empty
    end
  end

  describe "esquema y payload (criterio 6)" do
    it "un evento sin esquema registrado lanza Events::UnknownEvent" do
      expect { Tenancy.with_context(organization:) { described_class.publish("test.sin_esquema.v1", { a: 1 }) } }
        .to raise_error(Events::UnknownEvent, /test\.sin_esquema\.v1/)
    end

    it "un payload que no cumple su esquema lanza Events::InvalidPayload con el detalle y no escribe" do
      expect { Tenancy.with_context(organization:) { described_class.publish(event_name, { size: "grande" }) } }
        .to raise_error(Events::InvalidPayload) { |error| expect(error.message).to include(event_name).and include("thing_id") }

      expect(stored_events).to be_empty
    end

    it "un campo no declarado se rechaza si el esquema cierra additionalProperties" do
      expect { Tenancy.with_context(organization:) { described_class.publish(event_name, { thing_id: "t", extra: 1 }) } }
        .to raise_error(Events::InvalidPayload)
    end

    it "un nombre con mala forma lanza Events::UnknownEvent" do
      expect { Tenancy.with_context(organization:) { described_class.publish("Mal Nombre", {}) } }
        .to raise_error(Events::UnknownEvent)
    end

    it "valida antes de comprobar la transacción: un payload malo falla con InvalidPayload en cualquier contexto" do
      ActsAsTenant.with_tenant(organization) do
        expect { described_class.publish(event_name, { size: 1 }) }.to raise_error(Events::InvalidPayload)
      end
    end
  end

  describe "sin organización" do
    it "lanza NoTenantSet dentro de una transacción pero sin tenant" do
      expect { ApplicationRecord.transaction { described_class.publish(event_name, { thing_id: "t" }) } }
        .to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end
  end
end

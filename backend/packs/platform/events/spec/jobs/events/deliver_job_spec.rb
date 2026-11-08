require "rails_helper"

RSpec.describe Events::DeliverJob do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:event_name) { "test.thing_happened.v1" }
  let(:calls) { [] }
  let!(:outbox_event) { create_in(organization, :outbox_event, name: event_name, payload: { "thing_id" => "t-1" }) }

  before do
    seen = calls
    Events.subscribe(event_name, as: "test.audit") do |event|
      seen << { event:, tenant: ActsAsTenant.current_tenant, organization_id: Current.context&.organization&.id }
    end
  end

  # Entrega como lo hace el relay: el organization_id viaja en el payload del job y el middleware abre el contexto.
  def deliver(event = outbox_event, subscriber = "test.audit", org: event.organization_id)
    described_class.set("organization_id" => org).perform_async(event.id, subscriber)
    described_class.drain
  end

  def processed_count = with_tenant(organization) { Events::ProcessedEvent.where(event_id: outbox_event.id).count }

  it "se encola en la cola critical" do
    expect(described_class.get_sidekiq_options["queue"]).to eq("critical")
  end

  describe "contexto de tenant (criterio 4)" do
    it "invoca al suscriptor con la organización del evento como tenant actual" do
      deliver

      expect(calls.size).to eq(1)
      expect(calls.first).to include(tenant: organization, organization_id: organization.id)
    end

    it "entrega un Events::Event con el id, el nombre y el payload del evento" do
      deliver

      expect(calls.first[:event]).to have_attributes(id: outbox_event.id, name: event_name, payload: { "thing_id" => "t-1" }, organization_id: organization.id)
    end

    it "dentro del suscriptor, consultar datos de otra organización falla" do
      foreign_company = create_in(other_organization, :company)
      attempts = []
      Events.subscribe(event_name, as: "test.intruder") do |_event|
        attempts << [ Tenancy::Company.exists?(foreign_company.id), (Tenancy::Company.find(foreign_company.id) rescue :not_found) ] # rubocop:disable Style/RescueModifier
      end

      deliver(outbox_event, "test.intruder")

      expect(attempts).to eq([ [ false, :not_found ] ])
    end

    it "un evento de una organización no se entrega en el contexto de otra" do
      expect { deliver(outbox_event, "test.audit", org: other_organization.id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(calls).to be_empty
    end
  end

  describe "idempotencia (criterio 3)" do
    it "registra el procesamiento en processed_events" do
      deliver

      expect(with_tenant(organization) { Events::ProcessedEvent.pluck(:event_id, :subscriber) }).to eq([ [ outbox_event.id, "test.audit" ] ])
    end

    it "el mismo evento entregado dos veces al mismo suscriptor produce el efecto una vez" do
      2.times { deliver }

      expect(calls.size).to eq(1)
      expect(processed_count).to eq(1)
    end

    it "el mismo evento para suscriptores distintos se procesa una vez por suscriptor" do
      seen = calls
      Events.subscribe(event_name, as: "test.second") { |event| seen << { event: } }

      deliver
      deliver(outbox_event, "test.second")

      expect(calls.size).to eq(2)
      expect(processed_count).to eq(2)
    end
  end

  describe "fallos" do
    it "si el suscriptor lanza, no queda marca en processed_events y la entrega se puede reintentar" do
      attempts = 0
      Events.subscribe(event_name, as: "test.flaky") { |_event| (attempts += 1) == 1 ? raise("boom") : nil }

      expect { deliver(outbox_event, "test.flaky") }.to raise_error("boom")
      expect(with_tenant(organization) { Events::ProcessedEvent.where(subscriber: "test.flaky").count }).to eq(0)

      deliver(outbox_event, "test.flaky")

      expect(attempts).to eq(2)
      expect(with_tenant(organization) { Events::ProcessedEvent.where(subscriber: "test.flaky").count }).to eq(1)
    end

    it "lo que el suscriptor escribió en la base se revierte junto con la marca" do
      Events.subscribe(event_name, as: "test.writer") do |_event|
        create(:company)
        raise "boom"
      end

      expect { deliver(outbox_event, "test.writer") }.to raise_error("boom")

      expect(with_tenant(organization) { Tenancy::Company.count }).to eq(0)
    end

    it "un suscriptor desconocido lanza Events::UnknownSubscriber" do
      expect { deliver(outbox_event, "test.no_existe") }.to raise_error(Events::UnknownSubscriber, /test\.no_existe/)
    end

    it "un evento que ya no existe lanza RecordNotFound" do
      ghost = Events::Event.new(id: SecureRandom.uuid, name: event_name, organization_id: organization.id, payload: {}, metadata: {}, occurred_at: Time.current)

      expect { deliver(ghost) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

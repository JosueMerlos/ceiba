require "rails_helper"

RSpec.describe Events::Relay do
  let(:organization) { create(:organization) }
  let(:event_name) { "test.thing_happened.v1" }

  before do
    Events.subscribe(event_name, as: "test.audit") { |_event| nil }
    Events.subscribe(event_name, as: "test.notify", queue: "notifications") { |_event| nil }
  end

  def pending_event(org = organization, **) = create_in(org, :outbox_event, name: event_name, **)

  def enqueued = Sidekiq::Queues.jobs_by_queue.values.flatten.select { |job| job["class"] == "Events::DeliverJob" }

  def states(org = organization) = with_tenant(org) { Events::OutboxEvent.order(:id).pluck(:published_at, :attempts, :last_error) }

  describe ".call" do
    it "encola un DeliverJob por suscriptor, en su cola, con el organization_id del evento" do
      event = pending_event

      described_class.call

      expect(enqueued).to contain_exactly(
        a_hash_including("args" => [ event.id, "test.audit" ], "queue" => "critical", "organization_id" => organization.id),
        a_hash_including("args" => [ event.id, "test.notify" ], "queue" => "notifications", "organization_id" => organization.id)
      )
    end

    it "marca el evento como publicado y devuelve cuántos publicó" do
      pending_event

      expect(described_class.call).to eq(1)
      expect(states.first.first).to be_within(5.seconds).of(Time.current)
    end

    it "no vuelve a publicar un evento ya publicado" do
      pending_event
      described_class.call
      Sidekiq::Job.clear_all

      expect(described_class.call).to eq(0)
      expect(enqueued).to be_empty
    end

    it "un evento sin suscriptores se marca publicado sin encolar nada" do
      create_in(organization, :outbox_event, name: "test.sin_nadie.v1")

      expect(described_class.call).to eq(1)
      expect(enqueued).to be_empty
    end

    it "recorre TODAS las organizaciones, cada evento con su organización" do
      other = create(:organization)
      mine = pending_event
      theirs = pending_event(other)

      described_class.call

      expect(enqueued.select { |job| job["args"].last == "test.audit" }.to_h { |job| [ job["args"].first, job["organization_id"] ] })
        .to eq(mine.id => organization.id, theirs.id => other.id)
    end

    it "toma lotes ordenados por id hasta vaciar los pendientes" do
      events = Array.new(5) { pending_event }

      expect(described_class.call(batch_size: 2)).to eq(5)
      expect(enqueued.select { |job| job["args"].last == "test.audit" }.map { |job| job["args"].first }).to eq(events.map(&:id).sort)
      expect(states.map(&:first)).to all(be_present)
    end

    it "NO usa más de batch_size filas por lote (un lote por transacción)" do
      Array.new(5) { pending_event }
      sizes = []
      allow(described_class).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap { |relay| allow(relay).to receive(:publish).and_wrap_original { |m, events| sizes << events.size && m.call(events) } }
      end

      described_class.call(batch_size: 2)

      expect(sizes).to eq([ 2, 2, 1 ])
    end

    it "pide las filas con FOR UPDATE SKIP LOCKED" do
      pending_event
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.call }

      expect(queries.grep(/FOR UPDATE SKIP LOCKED/)).not_to be_empty
    end
  end

  describe "cuando Redis falla" do
    before { allow(Sidekiq::Client).to receive(:push_bulk).and_raise(RedisClient::CannotConnectError, "Redis caído") }

    it "el evento sigue pendiente, con el intento y el error registrados, y se lanza el error" do
      pending_event

      expect { described_class.call }.to raise_error(RedisClient::CannotConnectError)

      published_at, attempts, last_error = states.first
      expect([ published_at, attempts, last_error ]).to match([ nil, 1, /Redis caído/ ])
    end

    it "cada reintento suma un intento" do
      pending_event

      2.times { expect { described_class.call }.to raise_error(RedisClient::CannotConnectError) }

      expect(states.first[1]).to eq(2)
    end

    it "cuando Redis vuelve, el siguiente relay lo publica" do
      pending_event
      expect { described_class.call }.to raise_error(RedisClient::CannotConnectError)

      allow(Sidekiq::Client).to receive(:push_bulk).and_call_original

      expect(described_class.call).to eq(1)
      expect(enqueued.size).to eq(2)
    end
  end
end

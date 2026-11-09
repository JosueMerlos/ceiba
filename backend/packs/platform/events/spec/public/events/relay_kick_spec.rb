require "rails_helper"

RSpec.describe "Disparo del relay tras el commit" do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }

  before do
    Events::RelayKick.reset!
    register_event_schema("test.thing_happened.v1")
  end

  def relay_jobs = Sidekiq::Queues.jobs_by_queue.values.flatten.select { |job| job["class"] == "Events::RelayJob" }

  def publish = Tenancy.with_context(organization:) { Events.publish("test.thing_happened.v1", { thing_id: "t-1" }) }

  it "al confirmarse la transacción que publicó, encola un RelayJob (optimización; el cron es la red de seguridad)" do
    publish

    expect(relay_jobs.size).to eq(1)
  end

  it "NO lo encola mientras la transacción no se ha confirmado" do
    Tenancy.with_context(organization:) do
      Events.publish("test.thing_happened.v1", { thing_id: "t-1" })

      expect(relay_jobs).to be_empty
    end
  end

  it "no lo encola si la transacción hace rollback" do
    ApplicationRecord.transaction(requires_new: true) do
      Tenancy.with_context(organization:) { Events.publish("test.thing_happened.v1", { thing_id: "t-1" }) }
      raise ActiveRecord::Rollback
    end

    expect(relay_jobs).to be_empty
  end

  it "varias publicaciones en la MISMA transacción disparan UN solo relay" do
    Tenancy.with_context(organization:) { 3.times { Events.publish("test.thing_happened.v1", { thing_id: "t" }) } }

    expect(relay_jobs.size).to eq(1)
  end

  it "una transacción posterior vuelve a disparar (el aviso no queda pegado)" do
    publish
    publish

    expect(relay_jobs.size).to eq(2)
  end

  it "tras un rollback el siguiente commit dispara igualmente" do
    organization # se crea antes: dentro del savepoint revertido desaparecería
    ApplicationRecord.transaction(requires_new: true) do
      Tenancy.with_context(organization:) { Events.publish("test.thing_happened.v1", { thing_id: "t-1" }) }
      raise ActiveRecord::Rollback
    end
    publish

    expect(relay_jobs.size).to eq(1)
  end

  it "con Redis caído, tras el primer fallo no se vuelve a intentar durante unos segundos (no hay espera por COMMIT)" do
    allow(Events::RelayJob).to receive(:perform_async).and_raise(RedisClient::CannotConnectError, "Redis caído")

    3.times { publish }

    expect(Events::RelayJob).to have_received(:perform_async).once
  end

  it "pasada la pausa vuelve a intentar" do
    allow(Events::RelayJob).to receive(:perform_async).and_raise(RedisClient::CannotConnectError, "Redis caído")
    publish
    travel_to(Events::RelayKick::BACKOFF.from_now + 1) { publish }

    expect(Events::RelayJob).to have_received(:perform_async).twice
  end

  it "si Redis falla al disparar, el evento queda confirmado y publish no falla" do
    allow(Events::RelayJob).to receive(:perform_async).and_raise(RedisClient::CannotConnectError, "Redis caído")

    expect { publish }.not_to raise_error
    expect(with_tenant(organization) { Events::OutboxEvent.pending.count }).to eq(1)
  end
end

require "rails_helper"

RSpec.describe Events::RelayJob do
  let(:organization) { create(:organization) }

  it "es un job del sistema (tenant: false), de la cola critical y sin reintentos de Sidekiq" do
    expect(described_class.get_sidekiq_options).to include("queue" => "critical", "tenant" => false, "retry" => false)
  end

  it "se puede encolar sin organización" do
    expect { described_class.perform_async }.not_to raise_error
  end

  it "publica los eventos pendientes" do
    Events.subscribe("test.thing_happened.v1", as: "test.audit") { |_event| nil }
    create_in(organization, :outbox_event, name: "test.thing_happened.v1")

    described_class.new.perform

    expect(with_tenant(organization) { Events::OutboxEvent.pending.count }).to eq(0)
    expect(Sidekiq::Queues.jobs_by_queue.values.flatten.count { |job| job["class"] == "Events::DeliverJob" }).to eq(1)
  end

  it "un fallo del relay se reporta al error reporter y NO se propaga (el cron lo reintenta en 5 s)" do
    reports = []
    subscriber = Class.new { define_method(:report) { |error, **opts| reports << [ error.message, opts[:handled] ] } }.new
    Rails.error.subscribe(subscriber)
    allow(Events::Relay).to receive(:call).and_raise(RedisClient::CannotConnectError, "Redis caído")

    expect { described_class.new.perform }.not_to raise_error
    expect(reports).to eq([ [ "Redis caído", true ] ])
  ensure
    Rails.error.unsubscribe(subscriber)
  end
end

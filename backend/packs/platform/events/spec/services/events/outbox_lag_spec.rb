require "rails_helper"

RSpec.describe Events::OutboxLag do
  let(:organization) { create(:organization) }

  it "sin pendientes: 0 pendientes y lag 0" do
    expect(described_class.measure).to eq(pending: 0, oldest_age_seconds: 0)
  end

  it "cuenta los pendientes de todas las organizaciones y mide la edad del más antiguo" do
    other = create(:organization)
    create_in(organization, :outbox_event, occurred_at: 90.seconds.ago)
    create_in(other, :outbox_event, occurred_at: 10.seconds.ago)
    create_in(organization, :outbox_event, published_at: Time.current)

    result = described_class.measure

    expect(result[:pending]).to eq(2)
    expect(result[:oldest_age_seconds]).to be_between(89, 95)
  end

  it "publica la medición como notificación outbox_lag.events (para la alerta de M0.13) y la escribe en el log" do
    create_in(organization, :outbox_event, occurred_at: 30.seconds.ago)
    payloads = []
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)

    ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, "outbox_lag.events") { described_class.report }

    expect(payloads.first).to include(pending: 1)
    expect(logged.string).to match(/events\.outbox_lag pending=1 oldest_age_seconds=\d+/)
  ensure
    Rails.logger = original
  end
end

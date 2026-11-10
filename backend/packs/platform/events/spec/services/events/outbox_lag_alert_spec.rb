require "rails_helper"

# Criterio 6 de M0.13: con eventos sin publicar desde hace más de 5 min, el chequeo (Events::OutboxLagJob, cada minuto) emite
# una alerta. La alerta es un error reportado por Rails.error, que Sentry recoge (config/middleware/sentry_setup.rb).
RSpec.describe Events::OutboxLagAlert do
  let(:organization) { create(:organization) }
  let(:reports) { [] }
  let(:subscriber) do
    Class.new do
      def initialize(reports) = @reports = reports
      def report(error, handled:, severity:, context:, source: nil) = @reports << { error:, handled:, severity:, context: }
    end.new(reports)
  end

  around do |example|
    Rails.error.subscribe(subscriber)
    example.run
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  it "criterio 6: el chequeo con un evento sin publicar desde hace más de 5 min emite una alerta con el detalle", :aggregate_failures do
    create_in(organization, :outbox_event, occurred_at: 6.minutes.ago)

    Events::OutboxLagJob.new.perform

    expect(reports.size).to eq(1)
    expect(reports.first).to include(handled: true, severity: :error)
    expect(reports.first[:error]).to be_a(Events::OutboxLagExceeded)
    expect(reports.first[:context]).to include(pending: 1, threshold_seconds: 300, oldest_age_seconds: a_value >= 360)
  end

  it "el mensaje es estable (Sentry agrupa todas las alertas en una sola incidencia); las cifras van en el contexto" do
    create_in(organization, :outbox_event, occurred_at: 9.minutes.ago)

    Events::OutboxLag.report

    expect(reports.first[:error].message).to eq("El outbox tiene eventos sin publicar desde hace más de 5 minutos")
  end

  it "con el evento pendiente más antiguo de 4 min no alerta" do
    create_in(organization, :outbox_event, occurred_at: 4.minutes.ago)

    Events::OutboxLag.report

    expect(reports).to be_empty
  end

  it "sin eventos pendientes no alerta" do
    create_in(organization, :outbox_event, occurred_at: 1.hour.ago, published_at: 59.minutes.ago)

    Events::OutboxLag.report

    expect(reports).to be_empty
  end

  it "el umbral se cambia con OUTBOX_LAG_ALERT_SECONDS" do
    stub_const("ENV", ENV.to_h.merge("OUTBOX_LAG_ALERT_SECONDS" => "60"))
    create_in(organization, :outbox_event, occurred_at: 2.minutes.ago)

    Events::OutboxLag.report

    expect(reports.first[:context]).to include(threshold_seconds: 60)
  end
end

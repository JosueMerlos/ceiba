require "rails_helper"
require Rails.root.join("config/middleware/sentry_setup").to_s

# Verificación manual del criterio 4 de M0.13 (necesita un DSN real): `bin/rails sentry:test[<organization_id>]`.
# Aquí se prueba el mecanismo con un transporte falso.
RSpec.describe Observability::SentryCheck do
  include TenancyHelpers

  let(:organization) { new_organization }
  let(:events) { Sentry.get_current_client.transport.events.map(&:to_h) }

  after do
    Sentry.close
    SentrySetup.init(env: {}, rails_env: "test")
    purge_organizations(organization)
  end

  def init_sentry
    Sentry.init do |config|
      SentrySetup.configure(config, env: { "SENTRY_DSN" => "http://12345:67890@sentry.localdomain/sentry/42" }, rails_env: "production")
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
    end
  end

  it "sin DSN no hace nada y lo dice (no hay forma de verificar sin un DSN)" do
    SentrySetup.init(env: {}, rails_env: "test")

    expect(described_class.run(organization_id: organization.id)).to eq(:disabled)
    expect(Observability::SentryTestJob.jobs).to be_empty
  end

  it "con DSN envía un error de prueba con organization_id y encola un job que falla para verlo también desde Sidekiq", :aggregate_failures do
    init_sentry

    expect(described_class.run(organization_id: organization.id)).to eq(:sent)

    expect(events.first[:tags]).to include(organization_id: organization.id)
    expect(events.first.dig(:exception, :values, 0, :value)).to include("prueba")
    expect(Observability::SentryTestJob.jobs.size).to eq(1)
    expect(Observability::SentryTestJob.jobs.first["organization_id"]).to eq(organization.id)
  end

  it "el job de prueba lanza un error reconocible" do
    expect { Observability::SentryTestJob.new.perform }.to raise_error(Observability::SentryTestJob::TestError, /prueba/)
  end
end

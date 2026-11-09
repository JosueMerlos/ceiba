require "rails_helper"
require Rails.root.join("config/middleware/sentry_setup").to_s
require Rails.root.join("config/middleware/job_observability").to_s

# M0.13 (criterio 4, parte automática): los errores llegan a Sentry con el tenant y el job, sin PII, y con el release.
# El envío real necesita un DSN: ver las notas de cierre (verificación manual).
RSpec.describe SentrySetup, type: :request do
  include_context "con endpoints de prueba de la API"

  let(:dsn) { "http://12345:67890@sentry.localdomain/sentry/42" }
  let(:organization_id) { "0198f0a0-0000-7000-8000-0000000000aa" }
  let(:events) { Sentry.get_current_client.transport.events }
  let(:captured) { wait_for_events.map(&:to_h) }

  # El envío es asíncrono: espera a que el hilo de fondo entregue al menos un evento.
  def wait_for_events(count = 1)
    Timeout.timeout(5) { sleep 0.01 until Sentry.get_current_client.transport.events.size >= count }
    Sentry.get_current_client.transport.events
  end

  def init_with_dummy_transport(env = {})
    Sentry.init do |config|
      described_class.configure(config, env: { "SENTRY_DSN" => dsn }.merge(env), rails_env: "production")
      config.transport.transport_class = Sentry::DummyTransport
      # Hilos de fondo POR DEFECTO, como en producción: before_send corre en el hilo del worker de Sentry, donde Current y
      # LogContext (por hilo) están vacíos. Los tags tienen que ponerse al capturar, en el hilo de la request o del job.
    end
  end

  before { init_with_dummy_transport("APP_RELEASE" => "ceiba@abc1234") }

  after do
    Observability::LogContext.reset
    Current.reset
    Sentry.close
    described_class.init(env: {}, rails_env: "test")
  end

  it "está DESACTIVADO en test y sin DSN: ninguna request de la suite sale hacia Sentry" do
    Sentry.close
    described_class.init(env: {}, rails_env: "test")

    expect(Sentry.configuration.sending_allowed?).to be(false)
    expect(Sentry.configuration.dsn).to be_nil
  end

  it "con DSN fuera de test queda activo, con el release y el entorno indicados por ENV" do
    expect(Sentry.configuration.sending_allowed?).to be(true)
    expect(Sentry.configuration.release).to eq("ceiba@abc1234")
    expect(Sentry.configuration.environment).to eq("production")
  end

  it "el log interno del SDK sale por el logger de Rails (JSON), no por STDOUT en texto plano" do
    expect(Sentry.configuration.sdk_logger).to eq(Rails.logger)
  end

  it "no envía datos personales por defecto (send_default_pii false)" do
    expect(Sentry.configuration.send_default_pii).to be(false)
  end

  it "etiqueta el error con la organización, la empresa y la sucursal recordadas por Tenancy" do
    Observability::LogContext.organization_id = organization_id
    Observability::LogContext.company_id = "company-1"
    Observability::LogContext.branch_id = "branch-1"

    Sentry.capture_exception(RuntimeError.new("fallo"))

    expect(captured.first[:tags]).to include(organization_id:, company_id: "company-1", branch_id: "branch-1")
  end

  it "etiqueta el tipo y el id del principal, nunca su correo" do
    Current.principal = Identity::Principal::User.new(id: "u-1", email: "ana@ceiba.test", full_name: "Ana Pérez")

    Sentry.capture_exception(RuntimeError.new("fallo"))

    expect(captured.first[:tags]).to include(principal_type: "user", principal_id: "u-1")
    expect(captured.first.to_json).not_to include("ana@ceiba.test", "Ana Pérez")
  end

  it "criterio 4: un error en un job lleva organization_id y el nombre del job, en el ORDEN REAL de Sidekiq" do
    job = { "class" => "Events::DeliverJob", "jid" => "abc123", "queue" => "critical", "organization_id" => organization_id, "args" => [ "ana@ceiba.test" ] }
    config = Sidekiq::Config.new.tap { |c| c.logger = Sidekiq::Logger.new(StringIO.new) }
    job_logger = JobObservability::JobLogger.new(config)
    error = nil

    # processor.rb: el middleware de Sentry y el job corren DENTRO de prepare; el error handler (handle_exception) corre FUERA,
    # cuando prepare ya terminó y LogContext se reinició.
    job_logger.prepare(job) do
      Sentry::Sidekiq::SentryContextServerMiddleware.new.call(Object.new, job, "critical") { raise "falló" }
    rescue RuntimeError => e
      error = e
    end
    expect(Observability::LogContext.organization_id).to be_nil
    Sentry::Sidekiq::ErrorHandler.new.call(error, { context: "Job raised exception", job: }, config)

    expect(captured.first[:tags]).to include(organization_id:, job: "Events::DeliverJob")
    expect(captured.first.to_json).not_to include("ana@ceiba.test")
  end

  it "quita los correos de los mensajes de error" do
    Sentry.capture_exception(ActiveRecord::RecordNotFound.new("Couldn't find Identity::User with email=ana@ceiba.test"))
    Sentry.capture_message("no se pudo enviar a otra@ceiba.test")

    texts = captured.flat_map { |event| [ event[:message], *event.dig(:exception, :values)&.pluck(:value) ] }.compact
    expect(texts.join).not_to include("ana@ceiba.test", "otra@ceiba.test")
    expect(texts.join).to include("[email]")
  end

  it "filtra con filter_parameters los datos extra del evento" do
    Sentry.capture_message("hola", extra: { "password" => "hunter2", "phone" => "8888-7777", "limit" => 20 })

    expect(captured.first[:extra]).to include(password: "[FILTERED]", phone: "[FILTERED]", limit: 20)
  end

  it "un 500 de la API (rescatado por Api::ErrorHandling) llega a Sentry por Rails.error", :aggregate_failures do
    ApiProbes.define_controller!
    Rails.application.reload_routes_unless_loaded
    get "/api/v1/probes/boom"

    expect(response).to have_http_status(:internal_server_error)
    expect(captured.size).to eq(1)
    expect(captured.first.dig(:exception, :values, 0, :type)).to eq("RuntimeError")
    expect(captured.first[:contexts].values_at(:"rails.error", "rails.error").compact.first).to include(code: "internal.error", request_id: response.headers["X-Request-Id"])
  end

  it "se suscribe al reporter de errores de Rails (sin eso los 500 rescatados no llegarían)" do
    expect(Sentry.configuration.rails.register_error_subscriber).to be(true)
  end
end

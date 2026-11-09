require "rails_helper"
require Rails.root.join("config/middleware/job_observability").to_s

# M0.13: cada job deja líneas JSON con el mismo esquema que las requests (organization_id, jid, clase, duración), sin
# argumentos (pueden llevar datos personales) y deja el tenant en Observability::LogContext para Sentry.
RSpec.describe JobObservability do
  let(:output) { StringIO.new }
  let(:organization_id) { "0198f0a0-0000-7000-8000-0000000000aa" }
  let(:job) do
    { "class" => "Events::DeliverJob", "jid" => "abc123", "queue" => "critical", "organization_id" => organization_id, "args" => [ "ana@ceiba.test" ] }
  end
  let(:config) do
    Sidekiq::Config.new.tap do |config|
      config.logger = Sidekiq::Logger.new(output)
      described_class.install(config)
    end
  end
  let(:job_logger) { config[:job_logger].new(config) }
  let(:lines) { output.string.lines.map { |line| JSON.parse(line) } }

  after { Observability::LogContext.reset }

  def run_job(job_logger, job, &)
    job_logger.prepare(job) { job_logger.call(job, "critical", &) }
  end

  it "install fija el logger de jobs y el formateador JSON en la configuración de Sidekiq" do
    expect(config[:job_logger]).to eq(described_class::JobLogger)
    expect(config.logger.formatter).to be_a(described_class::Formatter)
  end

  it "una línea JSON por evento del job (start y done) con clase, jid, organization_id y duración en ms" do
    run_job(job_logger, job) { :ok }

    expect(lines.map { |line| line["msg"] }).to eq(%w[start done])
    expect(lines.last).to include(
      "level" => "INFO", "job_class" => "Events::DeliverJob", "jid" => "abc123", "organization_id" => organization_id
    )
    expect(lines.last["duration"]).to be_a(Numeric)
    expect(lines.first.keys).to include("ts", "pid")
  end

  it "un job que falla deja la línea fail y propaga el error" do
    expect { run_job(job_logger, job) { raise "boom" } }.to raise_error("boom")

    expect(lines.map { |line| line["msg"] }).to eq(%w[start fail])
    expect(lines.last).to include("organization_id" => organization_id)
  end

  it "no escribe los argumentos del job" do
    run_job(job_logger, job) { :ok }

    expect(output.string).not_to include("ana@ceiba.test")
  end

  it "un job del sistema (sin organización) deja organization_id en nil" do
    run_job(job_logger, job.except("organization_id")) { :ok }

    expect(lines.last).to include("organization_id" => nil)
  end

  it "durante el job, Observability::LogContext tiene la organización y la clase (Sentry los lee al capturar el error)" do
    seen = nil
    run_job(job_logger, job) { seen = Observability::LogContext.attributes.slice(:organization_id, :job_class) }

    expect(seen).to eq(organization_id:, job_class: "Events::DeliverJob")
  end

  it "al terminar el job no deja el tenant en LogContext (el siguiente job de otra organización no lo hereda)" do
    run_job(job_logger, job) { :ok }

    expect(Observability::LogContext.organization_id).to be_nil
  end
end

require "rails_helper"

RSpec.describe "Programación (sidekiq-cron) y colas del outbox" do
  describe Events::Schedule do
    def entry(name) = described_class.jobs.fetch(name)

    it "el relay corre cada 5 segundos (cron de 6 campos) en la cola critical" do
      expect(entry("events_relay")).to include("class" => "Events::RelayJob", "cron" => "*/5 * * * * *")
    end

    it "mide el lag cada minuto y purga a diario (de madrugada UTC)" do
      expect(entry("events_outbox_lag")).to include("class" => "Events::OutboxLagJob", "cron" => "* * * * *")
      expect(entry("events_purge_outbox")).to include("class" => "Events::PurgeOutboxJob", "cron" => a_string_matching(/\A\d+ [0-5]? ?\d \* \* \*\z|\A\d+ \d+ \* \* \*\z/))
      expect(entry("events_purge_processed")).to include("class" => "Events::PurgeProcessedJob")
    end

    it "todas las clases programadas existen y son jobs del sistema (tenant: false)" do
      described_class.jobs.each_value do |definition|
        job_class = definition.fetch("class").constantize
        expect(job_class.get_sidekiq_options["tenant"]).to be(false), "#{job_class} debe declarar tenant: false"
      end
    end

    it "el poll de sidekiq-cron es menor que 5 s (si no, el cron de segundos no se cumple)" do
      expect(described_class::POLL_INTERVAL).to be < 5
    end

    it "load! registra los jobs en sidekiq-cron (Redis real) y encolan sin organización", :redis do
      described_class.load!

      expect(Sidekiq::Cron::Job.all.map(&:name)).to include("events_relay", "events_outbox_lag", "events_purge_outbox", "events_purge_processed")

      Sidekiq::Cron::Job.find("events_relay").enque!

      expect(Sidekiq::Queue.new("critical").map { |job| job.item["class"] }).to eq([ "Events::RelayJob" ])
    ensure
      Sidekiq::Cron::Job.destroy_all!
    end

    it "load! es idempotente: cargarlo dos veces no duplica", :redis do
      2.times { described_class.load! }

      expect(Sidekiq::Cron::Job.all.count { |job| job.name == "events_relay" }).to eq(1)
    ensure
      Sidekiq::Cron::Job.destroy_all!
    end
  end

  describe "config/sidekiq.yml" do
    let(:config) { YAML.safe_load_file(Rails.root.join("config/sidekiq.yml"), symbolize_names: true) }

    it "declara las cuatro colas, critical primero y con más peso" do
      queues = config[:queues].map { |entry| Array(entry) }.to_h { |name, weight| [ name.to_s, weight ] }

      expect(queues.keys).to eq(%w[critical default notifications low])
      expect(queues["critical"]).to be > queues["default"]
      expect(queues["notifications"]).to be > queues["low"]
    end

    it "las colas de los suscriptores y de los jobs son las declaradas" do
      expect(Events::Subscriptions::QUEUES).to eq(%w[critical default notifications low])
    end
  end

  describe "Web UI de Sidekiq" do
    it "no está expuesta (llega en M4.01 con PlatformStaff)" do
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

      expect(paths.grep(/sidekiq/i)).to be_empty
      expect(defined?(Sidekiq::Web)).to be_nil
    end
  end
end

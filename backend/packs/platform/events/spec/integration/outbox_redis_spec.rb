require "rails_helper"

# Integración con Redis REAL (Sidekiq::Testing desactivado por la etiqueta :redis) y COMMIT real (sin fixtures
# transaccionales): criterios 2, 3 (con concurrencia) y 5 de M0.10.
RSpec.describe "Outbox con Redis real", :redis do
  self.use_transactional_tests = false

  let(:event_name) { "test.thing_happened.v1" }
  let!(:organizations) { Array.new(2) { |n| Tenancy::Organization.create!(name: "Integración #{n}") } }
  let(:organization) { organizations.first }
  let(:handled) { Queue.new }

  before do
    register_event_schema(event_name)
    queue = handled
    Events.subscribe(event_name, as: "test.audit") { |event| queue << [ event.id, ActsAsTenant.current_tenant.id ] }
  end

  after { purge_organizations(organizations) }

  # Un Redis inalcanzable: la misma falla que ve la aplicación con el contenedor de Redis detenido.
  def redis_down(&)
    dead_pool = Sidekiq::RedisConnection.create(url: "redis://127.0.0.1:1", size: 1, pool_name: "caido")
    Sidekiq::Client.via(dead_pool, &)
  end

  def publish(org = organization, id: "t-1")
    Tenancy.with_context(organization: org) { Events.publish(event_name, { thing_id: id }) }
  end

  # Barrera real: todos los hilos están creados y esperando antes de que ninguno arranque.
  def run_together(count)
    ready = Queue.new
    go = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        ready << index
        go.pop
        ActiveRecord::Base.connection_pool.with_connection { yield index }
      end
    end
    count.times { ready.pop }
    count.times { go << :go }
    threads.map(&:value)
  end

  def queued_jobs = Sidekiq::Queue.new("critical").select { |job| job.klass == "Events::DeliverJob" }.map(&:item)

  def state(org = organization) = with_tenant(org) { Events::OutboxEvent.order(:id).pluck(:published_at, :attempts) }

  # Ejecuta el job tal como lo haría un worker: sacado de Redis y pasando por la cadena de middleware de servidor.
  def process(item) = Events::DeliverJob.process_job(item)

  describe "Redis cae después del commit y vuelve (criterio 2)" do
    it "el evento confirmado con Redis caído se publica y se procesa cuando Redis vuelve", :aggregate_failures do
      event = redis_down { publish }

      expect(state).to eq([ [ nil, 0 ] ])
      expect { redis_down { Events::Relay.call } }.to raise_error(RedisClient::CannotConnectError)
      expect(state).to eq([ [ nil, 1 ] ]) # sigue pendiente, con el intento anotado

      expect(Events::Relay.call).to eq(1) # Redis vuelve

      expect(queued_jobs.map { |job| job["args"] }).to eq([ [ event.id, "test.audit" ] ])
      process(queued_jobs.first)

      expect(handled.pop(timeout: 1)).to eq([ event.id, organization.id ])
      expect(state.first.first).to be_present
    end

    it "publicar con Redis caído no falla: el disparo del relay es una optimización" do
      expect { redis_down { publish } }.not_to raise_error
    end

    it "el relay no pierde eventos aunque Redis falle varias veces seguidas" do
      3.times { |n| publish(id: "t-#{n}") }

      2.times { expect { redis_down { Events::Relay.call } }.to raise_error(RedisClient::CannotConnectError) }
      Events::Relay.call

      expect(queued_jobs.size).to eq(3)
      expect(state.map(&:first)).to all(be_present)
    end
  end

  describe "dos relays en paralelo (criterio 5)" do
    let(:total) { 500 }

    before do
      now = Time.current
      organizations.each do |org|
        rows = Array.new(total / 2) do |n|
          { organization_id: org.id, name: event_name, payload: { thing_id: "t-#{n}" }, metadata: {}, occurred_at: now, created_at: now, updated_at: now }
        end
        with_tenant(org) { Events::OutboxEvent.insert_all(rows) }
      end
    end

    def run_relays(count: 2, batch_size: 25)
      run_together(count) { Events::Relay.call(batch_size:) }
    end

    it "con 500 eventos pendientes, cada uno se publica exactamente una vez", :aggregate_failures do
      published = run_relays

      event_ids = queued_jobs.map { |job| job["args"].first }
      expect(published.sum).to eq(total)
      expect(event_ids.size).to eq(total)
      expect(event_ids.uniq.size).to eq(total)
      expect(organizations.sum { |org| state(org).count { |published_at, _| published_at } }).to eq(total)
    end

    it "con tres relays y lotes pequeños tampoco queda ningún pendiente ni se repite un evento" do
      published = run_relays(count: 3, batch_size: 10)
      event_ids = queued_jobs.map { |job| job["args"].first }

      expect(Events::OutboxLag.measure[:pending]).to eq(0)
      expect(event_ids.size).to eq(total)
      expect(event_ids.uniq.size).to eq(total)
      expect(published.count(&:positive?)).to be >= 2 # concurrencia real: el trabajo se repartió
    end

    it "cada DeliverJob lleva el organization_id de su evento" do
      run_relays

      by_org = queued_jobs.group_by { |job| job["organization_id"] }.transform_values(&:size)
      expect(by_org).to eq(organizations.to_h { |org| [ org.id, total / 2 ] })
    end
  end

  describe "entregas simultáneas del mismo evento (criterio 3 con concurrencia real)" do
    it "dos workers procesando el mismo job al mismo tiempo producen el efecto una vez" do
      effects = Queue.new
      Events.subscribe(event_name, as: "test.slow") { |_event| effects << :done && sleep(0.3) }
      event = publish
      Events::Relay.call
      item = queued_jobs.find { |job| job["args"].last == "test.slow" }

      run_together(2) { process(item.deep_dup) }

      expect(effects.size).to eq(1)
      expect(with_tenant(organization) { Events::ProcessedEvent.where(event_id: event.id, subscriber: "test.slow").count }).to eq(1)
    end
  end
end

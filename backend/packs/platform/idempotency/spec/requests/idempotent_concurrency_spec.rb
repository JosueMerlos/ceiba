require "rails_helper"

# Real race: two SIMULTANEOUS requests with the same key. No transactional fixtures: real COMMITs and separate
# connections are needed. The probe sleeps 0.6 s INSIDE the action so the second request arrives while the first is
# still running: the unique index makes it wait and then replay the stored response.
RSpec.describe "Idempotencia: peticiones concurrentes" do
  self.use_transactional_tests = false

  include_context "con endpoints de prueba de idempotencia"

  let!(:organization) { create(:organization) }
  let(:key) { SecureRandom.uuid }

  after { purge_organizations([ organization ]) }

  def post_company(name, delay: 0.6, idempotency_key: key)
    session = open_session
    session.post "/api/v1/idempotency_probes/organizations/#{organization.id}/slow_companies",
      params: { name:, delay: }, headers: { "Idempotency-Key" => idempotency_key }, as: :json
    session.response
  end

  def delayed(seconds)
    sleep seconds
    yield
  end

  def run_concurrently(*attempts)
    threads = attempts.map { |attempt| Thread.new { ApplicationRecord.connection_pool.with_connection { attempt.call } } }
    threads.map(&:value)
  end

  def companies_named(name) = with_tenant(organization) { Tenancy::Company.where(name:).to_a }

  it "dos peticiones simultáneas con la misma clave y el mismo cuerpo crean UN recurso y responden lo mismo" do
    responses = run_concurrently(-> { post_company("Carrera Uno") }, -> { post_company("Carrera Uno") })

    expect(responses.map(&:status)).to eq([ 201, 201 ])
    expect(responses.map(&:body).uniq.size).to eq(1)
    expect(companies_named("Carrera Uno").size).to eq(1)
  end

  it "una de las dos respuestas es la repetida (Idempotency-Replayed)" do
    responses = run_concurrently(-> { post_company("Carrera Marca") }, -> { post_company("Carrera Marca") })

    expect(responses.map { |response| response.headers["Idempotency-Replayed"] }).to contain_exactly(nil, "true")
  end

  it "con la misma clave y cuerpos distintos gana uno y el otro recibe 409 idempotency.key_reused" do
    responses = run_concurrently(-> { post_company("Carrera A") }, -> { post_company("Carrera B") })

    expect(responses.map(&:status)).to contain_exactly(201, 409)
    expect(responses.find { |response| response.status == 409 }.parsed_body["code"]).to eq("idempotency.key_reused")
    expect(companies_named("Carrera A").size + companies_named("Carrera B").size).to eq(1)
  end

  it "diez peticiones simultáneas con la misma clave crean un solo recurso" do
    responses = run_concurrently(*Array.new(10) { -> { post_company("Carrera Diez", delay: 0.3) } })

    expect(responses.map(&:status).uniq).to eq([ 201 ])
    expect(companies_named("Carrera Diez").size).to eq(1)
  end

  it "la espera está acotada: si la primera sigue en curso más allá del límite, la segunda recibe 409 idempotency.request_in_progress" do
    stub_const("Idempotency::Processor::LOCK_TIMEOUT", 0.3)

    responses = run_concurrently(-> { post_company("Carrera Lenta", delay: 1.5) }, -> { delayed(0.4) { post_company("Carrera Lenta", delay: 1.5) } })

    expect(responses.map(&:status)).to eq([ 201, 409 ])
    expect(responses.last.parsed_body).to include("code" => "idempotency.request_in_progress", "status" => 409)
    expect(companies_named("Carrera Lenta").size).to eq(1)
  end

  it "tras agotar la espera, el cliente puede reintentar y recibe la respuesta guardada" do
    stub_const("Idempotency::Processor::LOCK_TIMEOUT", 0.3)

    first, second = run_concurrently(-> { post_company("Carrera Reintento", delay: 1.0) }, -> { delayed(0.4) { post_company("Carrera Reintento", delay: 1.0) } })
    retried = post_company("Carrera Reintento", delay: 1.0)

    expect([ first.status, second.status, retried.status ]).to eq([ 201, 409, 201 ])
    expect(retried.body).to eq(first.body)
  end

  it "si la primera petición falla (rollback) mientras la segunda espera, la segunda SE EJECUTA" do
    first_fails = lambda do
      session = open_session
      session.post "/api/v1/idempotency_probes/organizations/#{organization.id}/slow_companies",
        params: { name: "", delay: 0.6 }, headers: { "Idempotency-Key" => key }, as: :json
      session.response
    end

    responses = run_concurrently(first_fails, -> { delayed(0.2) { post_company("", delay: 0.0) } })

    expect(responses.map(&:status)).to eq([ 422, 422 ]) # same invalid body: both are evaluated; neither consumed the key
    expect(with_tenant(organization) { Idempotency::Key.where(key:).count }).to eq(0)
  end

  it "con la primera fallida y la segunda con cuerpo válido, la segunda crea el recurso (la reserva desapareció)" do
    first_fails = lambda do
      session = open_session
      session.post "/api/v1/idempotency_probes/organizations/#{organization.id}/slow_companies",
        params: { name: "", delay: 0.6 }, headers: { "Idempotency-Key" => key }, as: :json
      session.response
    end

    responses = run_concurrently(first_fails, -> { delayed(0.2) { post_company("Carrera Recuperada", delay: 0.0) } })

    expect(responses.map(&:status)).to eq([ 422, 201 ])
    expect(companies_named("Carrera Recuperada").size).to eq(1)
  end

  it "la espera también está acotada al reemplazar una fila VENCIDA con la misma clave que otra transacción tiene bloqueada" do
    stub_const("Idempotency::Processor::LOCK_TIMEOUT", 0.3)
    with_tenant(organization) { create(:idempotency_key, principal_key: "anonymous", key:, expires_at: 1.hour.ago) }
    holder = hold_row_lock(key, seconds: 1.5)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = public_post("Carrera Vencida")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    holder.join

    expect(response.status).to eq(409)
    expect(response.parsed_body["code"]).to eq("idempotency.request_in_progress")
    expect(elapsed).to be < 1.0
  end

  # Another transaction holding the row locked (FOR UPDATE) for `seconds`; returns once the lock is held.
  def hold_row_lock(key, seconds:)
    locked = Queue.new
    thread = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute("SELECT 1 FROM idempotency_keys WHERE key = #{connection.quote(key)} FOR UPDATE")
          locked << true
          sleep seconds
        end
      end
    end
    locked.pop
    thread
  end

  def public_post(name)
    session = open_session
    session.post "/api/v1/idempotency_probes/organizations/#{organization.id}/slow_companies",
      params: { name:, delay: 0.0 }, headers: { "Idempotency-Key" => key }, as: :json
    session.response
  end
end

require "rails_helper"

# Carrera real (criterio 3, "incluida la carrera"): dos peticiones SIMULTÁNEAS con la misma clave. Sin fixtures
# transaccionales: hacen falta COMMITs y conexiones distintas. La sonda duerme 0,6 s DENTRO de la acción, así que la segunda
# llega mientras la primera aún no ha terminado: el índice único la hace esperar y luego repite la respuesta guardada.
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
end

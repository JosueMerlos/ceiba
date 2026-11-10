require "rails_helper"

# GETs of the API run in a READ-ONLY transaction (Access::RouteContextResolver). Nothing audits or stores idempotency
# keys on a GET: if something did, the database rejects it and the API answers 500. No transactional fixtures: the real
# BEGIN is what is observed.
RSpec.describe "Auditoría e idempotencia frente a la transacción de solo lectura de los GET", type: :request do
  self.use_transactional_tests = false

  include_context "con endpoints de prueba de idempotencia"

  let!(:world) { build_access_world }
  let!(:user) { user_with_role("org_admin", world) }
  let(:base) { "/api/v1/idempotency_probes/organizations/#{world.organization.id}" }

  before { allow(Api::ErrorReporter).to receive(:call) }

  after do
    with_tenant(world.organization) { Tenancy::Company.where(name: "Orden de filtros").delete_all }
    purge_organizations([ world.organization ], user_ids: [ user.id ])
    ApplicationRecord.connection.execute("DELETE FROM sessions WHERE user_id = #{ApplicationRecord.connection.quote(user.id)}")
    Identity::User.where(id: user.id).delete_all
  end

  it "Audit.record dentro de un GET falla (500) y no deja ningún evento" do
    sign_in(user)

    get "#{base}/audit_in_get"

    expect(response).to have_http_status(:internal_server_error)
    expect(Api::ErrorReporter).to have_received(:call).with(instance_of(ActiveRecord::StatementInvalid), any_args)
    expect(with_tenant(world.organization) { Audit::Event.where(action: "probe.read").count }).to eq(0)
  end

  it "declarar `idempotent` en un GET falla (la reserva es una escritura) en vez de guardar nada en silencio" do
    signed_in = sign_in(user)

    get "#{base}/idempotent_get", headers: { "Idempotency-Key" => SecureRandom.uuid, **signed_in.csrf_headers }

    expect(response).to have_http_status(:internal_server_error)
    expect(with_tenant(world.organization) { Idempotency::Key.count }).to eq(0)
  end

  it "un GET sin Idempotency-Key no toca idempotency_keys (el concern no escribe si no hay clave)" do
    sign_in(user)

    get "#{base}/idempotent_get"

    expect(response).to have_http_status(:ok)
  end

  it "los eventos de identidad (login) sí se escriben: auth_audit_events es global y el login no corre en la transacción de un GET" do
    sign_in(user)

    expect(Audit::AuthEvent.where(user_id: user.id, action: "auth.login_succeeded").count).to eq(1)
  end

  it "`idempotent` corre DENTRO del contexto de Access::Authorization: el principal ya es el de acceso y la clave queda por organización" do
    signed_in = sign_in(user)
    key = SecureRandom.uuid

    post "#{base}/companies", params: { name: "Orden de filtros" }, headers: { "Idempotency-Key" => key, **signed_in.csrf_headers }, as: :json

    stored = with_tenant(world.organization) { Idempotency::Key.find_by!(key:) }
    expect([ response.status, stored.principal_key, stored.organization_id ]).to eq([ 201, "user:#{user.id}", world.organization.id ])
  end
end

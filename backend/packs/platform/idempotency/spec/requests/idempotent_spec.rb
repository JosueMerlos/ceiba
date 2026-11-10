require "rails_helper"

# Idempotency::Idempotent concern: `idempotent :create` makes retrying a creation safe, over a probe that creates a
# company (a real, countable resource).
RSpec.describe "Idempotencia de escrituras (Idempotency-Key)" do
  include ActiveSupport::Testing::TimeHelpers
  include_context "con endpoints de prueba de idempotencia"

  let(:organization) { build_access_world.organization }
  let(:other_organization) { create(:organization) }
  # A user with membership in BOTH organizations: Access::Authorization opens the context from the route.
  let(:user) { user_with_role("org_admin", organization).tap { |member| user_with_role("org_admin", other_organization, user: member) } }
  let!(:signed_in) { sign_in(user) }
  let(:key) { SecureRandom.uuid }

  after { travel_back }

  def path(org = organization, kind = "companies") = "/api/v1/idempotency_probes/organizations/#{org.id}/#{kind}"

  def create_company(name: "Sucursal Uno", idempotency_key: key, org: organization, kind: "companies", browser: self, csrf: signed_in.csrf_headers)
    headers = idempotency_key ? csrf.merge("Idempotency-Key" => idempotency_key) : csrf
    browser.post path(org, kind), params: { name: }, headers:, as: :json
    browser.response
  end

  def companies_named(name) = with_tenant(organization) { Tenancy::Company.where(name:).to_a }

  describe "misma clave y mismo cuerpo (criterio 3)" do
    it "crea UN solo recurso y devuelve la misma respuesta (estado, cuerpo y Location)" do
      first = create_company
      first_snapshot = [ first.status, first.body, first.headers["Location"] ]
      second = create_company

      expect(first).to have_http_status(:created)
      expect([ second.status, second.body, second.headers["Location"] ]).to eq(first_snapshot)
      expect(companies_named("Sucursal Uno").size).to eq(1)
    end

    it "marca la repetición con Idempotency-Replayed: true y la primera no" do
      first = create_company
      expect(first.headers["Idempotency-Replayed"]).to be_nil

      expect(create_company.headers["Idempotency-Replayed"]).to eq("true")
    end

    it "la respuesta repetida conserva el Content-Type" do
      create_company

      expect(create_company.media_type).to eq("application/json")
    end

    it "guarda el cuerpo de la respuesta CIFRADO: el valor en la columna no contiene el texto" do
      create_company

      raw = ApplicationRecord.connection.select_value("SELECT response_body FROM idempotency_keys WHERE key = '#{key}'")
      expect(raw).to be_present
      expect(raw).not_to include("Sucursal Uno")
      expect(with_tenant(organization) { Idempotency::Key.find_by!(key:).response_body }).to include("Sucursal Uno")
    end

    it "guarda la respuesta con caducidad de 24 horas" do
      freeze_time do
        create_company

        stored = with_tenant(organization) { Idempotency::Key.find_by!(key:) }
        expect(stored).to have_attributes(response_status: 201, expires_at: 24.hours.from_now, principal_key: "user:#{user.id}")
      end
    end
  end

  describe "misma clave y otro cuerpo (criterio 4)" do
    it "responde 409 con el code idempotency.key_reused y no crea nada" do
      create_company(name: "Sucursal Uno")
      response = create_company(name: "Sucursal Dos")

      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("code" => "idempotency.key_reused", "status" => 409)
    end

    it "no crea el segundo recurso" do
      create_company(name: "Sucursal Uno")
      create_company(name: "Sucursal Dos")

      expect(companies_named("Sucursal Dos")).to be_empty
    end

    it "el 409 no revela el cuerpo guardado" do
      create_company(name: "Sucursal Uno")

      expect(create_company(name: "Sucursal Dos").body).not_to include("Sucursal Uno")
    end

    it "la misma clave y el mismo cuerpo en otra RUTA también es otro request (409)" do
      create_company
      response = create_company(kind: "companies_alias") # another path, same principal and body

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("idempotency.key_reused")
    end
  end

  describe "alcance de la clave" do
    it "claves distintas crean recursos distintos" do
      create_company(idempotency_key: SecureRandom.uuid)
      create_company(idempotency_key: SecureRandom.uuid)

      expect(companies_named("Sucursal Uno").size).to eq(2)
    end

    it "es por organización: la misma clave en otra organización no se repite" do
      create_company
      response = create_company(org: other_organization)

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
    end

    it "es por principal: otro usuario con la misma clave y cuerpo no recibe la respuesta del primero" do
      create_company
      browser = open_session
      other = sign_in(user_with_role("org_admin", organization), browser:)
      response = create_company(browser:, csrf: other.csrf_headers)

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
      expect(companies_named("Sucursal Uno").size).to eq(2)
    end

    it "un principal anónimo exige una clave con formato UUID (400 idempotency.key_invalid)" do
      response = create_company(kind: "public_companies", csrf: {}, idempotency_key: "clave-adivinable-1")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("idempotency.key_invalid")
      expect(companies_named("Sucursal Uno")).to be_empty
    end

    it "un principal autenticado puede usar cualquier clave válida (no solo UUID)" do
      expect(create_company(idempotency_key: "clave-libre-1")).to have_http_status(:created)
    end

    it "un principal anónimo (reserva pública) también es idempotente, en su propio alcance" do
      first = create_company(kind: "public_companies", csrf: {})
      second = create_company(kind: "public_companies", csrf: {})

      expect(second.body).to eq(first.body)
      expect(companies_named("Sucursal Uno").size).to eq(1)
      expect(with_tenant(organization) { Idempotency::Key.find_by!(key:).principal_key }).to eq("anonymous")
    end
  end

  describe "sin clave o con una clave inválida" do
    it "sin Idempotency-Key y `required: false` procesa cada petición" do
      create_company(idempotency_key: nil)
      create_company(idempotency_key: nil)

      expect(companies_named("Sucursal Uno").size).to eq(2)
    end

    it "con `required: true` y sin clave responde 400 idempotency.key_required" do
      response = create_company(idempotency_key: nil, kind: "required_companies")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("idempotency.key_required")
      expect(companies_named("Sucursal Uno")).to be_empty
    end

    [ "x" * 256, "con espacios", "tab\tinvalida", "ñandú" ].each do |invalid|
      it "rechaza la clave #{invalid.inspect[0, 20]} con 400 idempotency.key_invalid" do
        response = create_company(idempotency_key: invalid)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["code"]).to eq("idempotency.key_invalid")
      end
    end

    it "acepta una clave de 255 caracteres" do
      expect(create_company(idempotency_key: "k" * 255)).to have_http_status(:created)
    end
  end

  describe "respuestas de error" do
    it "una petición que falla (422) no consume la clave: el reintento con el cuerpo corregido se procesa" do
      failed = create_company(name: "")
      expect(failed).to have_http_status(:unprocessable_content)

      retried = create_company(name: "Sucursal Uno")

      expect(retried).to have_http_status(:created)
      expect(companies_named("Sucursal Uno").size).to eq(1)
    end

    it "el 422 repetido con el mismo cuerpo se vuelve a evaluar (no se guarda)" do
      2.times { expect(create_company(name: "")).to have_http_status(:unprocessable_content) }
      expect(with_tenant(organization) { Idempotency::Key.where(key:).count }).to eq(0)
    end

    it "una respuesta 4xx RENDERIZADA sin excepción tampoco consume la clave" do
      create_company(kind: "soft_fails")

      expect(with_tenant(organization) { Idempotency::Key.where(key:).count }).to eq(0)
    end

    it "tras un 4xx renderizado, la misma clave y el mismo cuerpo se vuelve a ejecutar" do
      first = create_company(kind: "soft_fails")
      second = create_company(kind: "soft_fails")

      expect([ first.status, second.status ]).to eq([ 422, 422 ])
      expect(second.headers["Idempotency-Replayed"]).to be_nil
    end

    it "sin contexto de tenancy el concern falla de forma clara (bug de programación, 500)" do
      post "/api/v1/idempotency_probes/no_context", headers: signed_in.csrf_headers.merge("Idempotency-Key" => key), as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body["code"]).to eq("internal.error")
    end
  end

  describe "expiración de 24 horas" do
    it "pasadas 23 horas la clave sigue repitiendo la respuesta" do
      first = create_company
      travel 23.hours
      relogged = sign_in(user)
      again = create_company(csrf: relogged.csrf_headers)

      expect(again.body).to eq(first.body)
    end

    it "pasadas 24 horas la clave caduca: la misma petición crea un recurso nuevo" do
      create_company
      travel 24.hours + 1.minute
      relogged = sign_in(user)
      again = create_company(csrf: relogged.csrf_headers)

      expect(again).to have_http_status(:created)
      expect(again.headers["Idempotency-Replayed"]).to be_nil
      expect(companies_named("Sucursal Uno").size).to eq(2)
    end

    it "tras caducar, la clave puede reutilizarse con otro cuerpo (sin 409)" do
      create_company(name: "Sucursal Uno")
      travel 25.hours
      relogged = sign_in(user)

      expect(create_company(name: "Sucursal Dos", csrf: relogged.csrf_headers)).to have_http_status(:created)
    end
  end
end

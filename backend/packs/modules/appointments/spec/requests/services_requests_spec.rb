require "rails_helper"

# Behavior of the service endpoints that the contract specs do not describe: idempotent creation and strict input types.
RSpec.describe "Servicios: peticiones" do
  let(:world) { build_access_world }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let!(:signed_in) { sign_in(manager) }
  let(:base) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/services" }
  let(:body) { { name: "Corte", duration_minutes: 30, price_minor: 20_000 } }

  before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

  def count = with_tenant(world.organization) { Appointments::Service.count }

  def create_service(params, user_headers: signed_in.csrf_headers, headers: {})
    post base, params:, headers: user_headers.merge(headers), as: :json
  end

  describe "Idempotency-Key al crear" do
    it "repetir la petición con la misma clave devuelve la misma respuesta y crea un solo servicio" do
      key = SecureRandom.uuid

      create_service(body, headers: { "Idempotency-Key" => key })
      first = [ response.status, response.body ]
      create_service(body, headers: { "Idempotency-Key" => key })

      expect([ response.status, response.body ]).to eq(first)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(count).to eq(1)
    end

    it "una repetición con la misma clave responde 403 si al usuario ya le quitaron el permiso (no repite la respuesta guardada)", :aggregate_failures do
      writer = user_with_custom_role(world, scope_level: "company", company: world.company_a, permissions: %w[appointments.service.manage])
      csrf = sign_in(writer).csrf_headers
      key = SecureRandom.uuid
      create_service(body, user_headers: csrf, headers: { "Idempotency-Key" => key })
      expect(response).to have_http_status(:created)
      Access::RolePermission.where(permission_key: "appointments.service.manage").delete_all

      create_service(body, user_headers: csrf, headers: { "Idempotency-Key" => key })

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
      expect(count).to eq(1)
    end
  end

  describe "tipos de entrada" do
    it "un precio que es texto o decimal responde 400 y no crea nada (el dinero es un entero)" do
      create_service(body.merge(price_minor: "20000"))
      expect(response).to have_http_status(:bad_request)

      create_service(body.merge(price_minor: 200.5))
      expect(response).to have_http_status(:bad_request)
      expect(count).to eq(0)
    end

    it "un nombre que no es texto o un active que no es booleano responde 400" do
      create_service(body.merge(name: 123))
      expect(response).to have_http_status(:bad_request)

      create_service(body.merge(active: "yes"))
      expect(response).to have_http_status(:bad_request)
      expect(count).to eq(0)
    end

    it "campos que no son del servicio (organization_id, archived_at) se ignoran" do
      create_service(body.merge(organization_id: SecureRandom.uuid, archived_at: Time.current.iso8601, company_id: world.company_b.id))

      expect(response).to have_http_status(:created)
      created = with_tenant(world.organization) { Appointments::Service.sole }
      expect(created).to have_attributes(organization_id: world.organization.id, company_id: world.company_a.id, archived_at: nil)
    end
  end
end

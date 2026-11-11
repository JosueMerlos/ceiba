require "rails_helper"

# Behavior of the customer endpoints that the contract specs do not describe: idempotent creation and strict input types.
RSpec.describe "Clientes: peticiones" do
  let(:world) { build_access_world }
  let(:user) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let!(:signed_in) { sign_in(user) }
  let(:base) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}/customers" }
  let(:count) { with_tenant(world.organization) { Customers::Customer.count } }

  def create_customer(body, headers: {})
    post base, params: body, headers: signed_in.csrf_headers.merge(headers), as: :json
  end

  describe "Idempotency-Key al crear" do
    it "repetir la petición con la misma clave devuelve la misma respuesta y crea un solo cliente" do
      key = SecureRandom.uuid
      body = { full_name: "Ana López", phone_e164: "8888-7777" }

      create_customer(body, headers: { "Idempotency-Key" => key })
      first = [ response.status, response.body ]
      create_customer(body, headers: { "Idempotency-Key" => key })

      expect([ response.status, response.body ]).to eq(first)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(count).to eq(1)
    end

    it "sin la cabecera la creación funciona igual (no es obligatoria)" do
      create_customer({ full_name: "Ana López", phone_e164: "8888-7777" })

      expect(response).to have_http_status(:created)
    end
  end

  describe "autorización al repetir" do
    it "una repetición con la misma clave responde 403 si al usuario ya le quitaron el permiso (no repite la respuesta guardada)" do
      writer = user_with_custom_role(world, scope_level: "branch", branch: world.branch_a1, permissions: %w[platform.customer.create])
      csrf = sign_in(writer).csrf_headers
      key = SecureRandom.uuid
      body = { full_name: "Ana López", phone_e164: "8888-7777" }
      post base, params: body, headers: csrf.merge("Idempotency-Key" => key), as: :json
      expect(response).to have_http_status(:created)
      Access::RolePermission.where(permission_key: "platform.customer.create").delete_all

      post base, params: body, headers: csrf.merge("Idempotency-Key" => key), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
    end
  end

  describe "tipos de entrada" do
    it "un campo que no es texto responde 400 y no crea nada" do
      create_customer({ full_name: 123, phone_e164: "8888-7777" })

      expect(response).to have_http_status(:bad_request)
      expect(count).to eq(0)
    end

    it "un objeto o un arreglo en un campo de texto responde 400 y no crea nada" do
      [ { phone_e164: { a: 1 } }, { full_name: [ "Ana" ] } ].each do |bad|
        create_customer({ full_name: "Ana", phone_e164: "8888-7777" }.merge(bad))

        expect(response).to have_http_status(:bad_request)
      end
      expect(count).to eq(0)
    end

    it "un teléfono con forma de E.164 que no es un número real responde 422 validation.failed en phone_e164" do
      create_customer({ full_name: "Ana", phone_e164: "+50511111111" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("field")).to eq([ "phone_e164" ])
      expect(count).to eq(0)
    end

    it "un filtro del listado que no es texto responde 400" do
      get "#{base}?name_prefix[]=a"

      expect(response).to have_http_status(:bad_request)
    end

    it "un filtro del listado con byte nulo responde 400" do
      get "#{base}?name_prefix=a%00b"

      expect(response).to have_http_status(:bad_request)
    end

    it "un texto con byte nulo en el cuerpo responde 400 y no crea nada" do
      create_customer({ full_name: "a\u0000b", phone_e164: "8888-7777" })

      expect(response).to have_http_status(:bad_request)
      expect(count).to eq(0)
    end

    it "campos ajenos (empresa, archivado, organización) se ignoran" do
      create_customer({ full_name: "Ana", phone_e164: "8888-7777", company_id: world.company_b.id, archived_at: Time.current, organization_id: create(:organization).id })

      expect(response).to have_http_status(:created)
      customer = with_tenant(world.organization) { Customers::Customer.sole }
      expect([ customer.company_id, customer.organization_id, customer.archived_at ]).to eq([ world.company_a.id, world.organization.id, nil ])
    end
  end

  describe "auditoría y respuesta sin datos de más" do
    it "el error 422 no repite el teléfono, el nombre ni el correo enviados" do
      create_customer({ full_name: "Ana Secreta", phone_e164: "999", email: "secreto@example.com" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to match(/Secreta|999|secreto/)
    end
  end
end

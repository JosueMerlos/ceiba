require "rails_helper"

# Resolución del contexto desde la RUTA organizations/:organization_id/companies/:company_id/branches/:branch_id, validada
# contra los memberships del principal (docs/architecture/03 y 04). 404 si el recurso no es visible para el principal; 403
# solo si es visible pero la acción no está permitida.
RSpec.describe "Contexto de la ruta y alcance de los memberships" do
  let(:world) { build_access_world }
  let(:organization) { world.organization }
  let(:base) { "/api/v1/organizations/#{organization.id}" }

  def get_as(user, path)
    sign_in(user)
    get path
  end

  def ids(response_body) = response_body.fetch("data").pluck("id")

  describe "criterio 1: branch_manager de A1 pide la sucursal A2 de la misma empresa" do
    let(:manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }

    it "recibe 404 (no revela que existe)" do
      get_as(manager, "#{base}/companies/#{world.company_a.id}/branches/#{world.branch_a2.id}")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("resource.not_found")
    end

    it "su propia sucursal sí la ve" do
      get_as(manager, "#{base}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "id")).to eq(world.branch_a1.id)
    end

    it "la empresa de otro grupo (B) también es 404" do
      get_as(manager, "#{base}/companies/#{world.company_b.id}/branches/#{world.branch_b1.id}")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "criterio 2: company_manager de A lista sucursales" do
    let(:manager) { user_with_role("company_manager", world, company: world.company_a) }

    it "ve todas las de A" do
      get_as(manager, "#{base}/companies/#{world.company_a.id}/branches")

      expect(response).to have_http_status(:ok)
      expect(ids(response.parsed_body)).to contain_exactly(world.branch_a1.id, world.branch_a2.id)
    end

    it "no puede listar las de la empresa B del mismo grupo: 404" do
      get_as(manager, "#{base}/companies/#{world.company_b.id}/branches")

      expect(response).to have_http_status(:not_found)
    end

    it "en el listado de empresas solo aparece la suya" do
      get_as(manager, "#{base}/companies")

      expect(ids(response.parsed_body)).to eq([ world.company_a.id ])
    end
  end

  describe "criterio 3: org_admin accede a cualquier empresa de su organización" do
    let(:admin) { user_with_role("org_admin", world) }

    it "lee ambas empresas, sus sucursales y la organización" do
      sign_in(admin)

      [ "", "/companies/#{world.company_a.id}", "/companies/#{world.company_b.id}",
        "/companies/#{world.company_b.id}/branches/#{world.branch_b1.id}", "/companies/#{world.company_a.id}/branches" ].each do |suffix|
        get "#{base}#{suffix}"
        expect(response).to have_http_status(:ok), "GET #{suffix} -> #{response.status}"
      end
    end
  end

  describe "criterio 4: usuario con memberships en dos organizaciones" do
    let(:other_world) { build_access_world }
    let(:user) do
      created = user_with_role("branch_manager", world, branch: world.branch_a1)
      user_with_role("org_admin", other_world, user: created)
    end

    it "en la ruta de X solo aplican los permisos de X (su rol de admin en Y no se filtra)" do
      get_as(user, "#{base}/companies/#{world.company_a.id}")

      expect(response).to have_http_status(:forbidden) # visible por su sucursal, pero company.read no es de branch_manager
    end

    it "en la ruta de Y aplican los de Y" do
      get_as(user, "/api/v1/organizations/#{other_world.organization.id}/companies/#{other_world.company_a.id}")

      expect(response).to have_http_status(:ok)
    end

    it "GET /organizations lista las dos" do
      get_as(user, "/api/v1/organizations")

      expect(ids(response.parsed_body)).to contain_exactly(organization.id, other_world.organization.id)
    end
  end

  describe "organización ajena" do
    let(:outsider) { user_with_role("org_owner", build_access_world) }

    it "es 404, idéntico al de una organización inexistente (no revela existencia)" do
      sign_in(outsider)
      get "/api/v1/organizations/#{organization.id}"
      foreign = response.parsed_body.except("request_id", "instance")
      get "/api/v1/organizations/0198f0a0-0000-7000-8000-000000000000"
      missing = response.parsed_body.except("request_id", "instance")

      expect(response).to have_http_status(:not_found)
      expect(foreign).to eq(missing)
    end

    it "también en rutas anidadas" do
      get_as(outsider, "#{base}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "empresa de la organización sin membership" do
    it "es 404 aunque el usuario sea miembro de la organización por otra empresa" do
      manager = user_with_role("company_manager", world, company: world.company_a)

      get_as(manager, "#{base}/companies/#{world.company_b.id}")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "403: visible pero la acción no está permitida" do
    it "un recepcionista ve su sucursal en la ruta pero no puede leerla (la matriz no se lo da)" do
      receptionist = user_with_role("receptionist", world, branch: world.branch_a1)

      get_as(receptionist, "#{base}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("access.forbidden")
    end

    it "un branch_manager lee su sucursal pero la empresa le da 403 (visible por su sucursal)" do
      manager = user_with_role("branch_manager", world, branch: world.branch_a1)

      get_as(manager, "#{base}/companies/#{world.company_a.id}")

      expect(response).to have_http_status(:forbidden)
    end

    it "el detalle de la organización: 403 para quien no es owner/admin" do
      manager = user_with_role("company_manager", world, company: world.company_a)

      get_as(manager, base)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "organización suspendida" do
    before { organization.update!(status: "suspended") }

    it "sus miembros reciben 403 access.organization_suspended en toda ruta bajo ella" do
      admin = user_with_role("org_admin", world)

      get_as(admin, "#{base}/companies")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("access.organization_suspended")
    end

    it "quien no es miembro sigue viendo 404 (la suspensión no revela existencia)" do
      outsider = user_with_role("org_owner", build_access_world)

      get_as(outsider, "#{base}/companies")

      expect(response).to have_http_status(:not_found)
    end

    it "sigue apareciendo en GET /organizations con su estado, para que la SPA lo explique" do
      admin = user_with_role("org_admin", world)

      get_as(admin, "/api/v1/organizations")

      expect(response.parsed_body["data"].find { |org| org["id"] == organization.id }).to include("status" => "suspended")
    end
  end

  describe "sin sesión" do
    it "es 401 antes que cualquier otra cosa" do
      get "#{base}/companies"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# El contexto sale SOLO de los parámetros de la RUTA (request.path_parameters), nunca de la query ni del cuerpo.
RSpec.describe "El contexto solo sale de la ruta" do
  let(:world) { build_access_world }
  let(:foreign) { build_access_world }

  before { sign_in(user_with_role("org_owner", world)) }

  it "GET /auth/session?organization_id=<ajena> no fija ningún contexto (la query se ignora)" do
    query = { organization_id: foreign.organization.id, company_id: foreign.company_a.id }
    allow(Tenancy).to receive(:with_context).and_call_original

    get "/api/v1/auth/session", params: query

    expect(response).to have_http_status(:ok)
    expect(Tenancy).not_to have_received(:with_context)
  end

  it "una query ?organization_id= en una ruta con contexto no sustituye al de la ruta" do
    get "/api/v1/organizations/#{world.organization.id}/companies", params: { organization_id: foreign.organization.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"].pluck("id")).to contain_exactly(world.company_a.id, world.company_b.id)
  end

  it "una sucursal sin empresa en los parámetros de la ruta es 404 (no se ignora)" do
    owner = user_with_role("org_owner", world)
    principal = Access::Principal::User.new(Identity::Principal::User.new(id: owner.id, email: owner.email, full_name: owner.full_name))

    expect do
      Access::RouteContextResolver.call(principal:, organization_id: world.organization.id, branch_id: world.branch_a1.id) { :nunca }
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

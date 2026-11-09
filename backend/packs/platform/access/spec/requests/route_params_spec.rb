require "rails_helper"

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

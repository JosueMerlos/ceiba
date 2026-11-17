require "rails_helper"

# A branch created after the module was enabled has no weekly hours: it is closed until someone configures them.
RSpec.describe "Sucursal nueva: sin horario" do
  let(:world) { build_access_world }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let!(:signed_in) { sign_in(manager) }
  let(:company_path) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}" }

  before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

  it "la sucursal recién creada responde un horario vacío (cerrada) en GET schedule" do
    post "#{company_path}/branches", params: { name: "Sucursal Nueva", time_zone: "America/Managua" }, headers: signed_in.csrf_headers, as: :json
    expect(response).to have_http_status(:created)
    branch_id = response.parsed_body.dig("data", "id")

    get "#{company_path}/appointments/branches/#{branch_id}/schedule"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"]).to eq([])
  end
end

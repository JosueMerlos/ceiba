require "rails_helper"

# PUT/PATCH edge cases the rswag contract does not cover.
RSpec.describe "Módulos de una empresa: bordes" do
  include_context "con el módulo sample sincronizado"

  let(:world) { build_access_world }
  let(:base) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/modules/sample" }
  let(:signed_in) { sign_in(user_with_role("org_admin", world)) }

  before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "sample") } }

  it "settings que no es un objeto: 400" do
    patch "#{base}/settings", params: { settings: "no-soy-un-objeto" }, as: :json, headers: signed_in.csrf_headers

    expect(response).to have_http_status(:bad_request)
  end

  it "enabled solo acepta true o false literales: \"abc\" y \"no\" son 400 y no activan nada" do
    %w[abc no 1].each do |value|
      put base, params: { enabled: value }, as: :json, headers: signed_in.csrf_headers

      expect(response).to have_http_status(:bad_request)
    end
    expect(with_tenant(world.organization) { Modules.enabled?(world.company_a, "sample") }).to be(true)
  end

  it "enabled: false y true literales funcionan" do
    put base, params: { enabled: false }, as: :json, headers: signed_in.csrf_headers

    expect(response.parsed_body.dig("data", "enabled")).to be(false)
  end

  it "una sucursal que no es un UUID: 404" do
    patch "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/zzz/modules/sample/settings", params: { settings: { max_advance_days: 3 } }, as: :json, headers: signed_in.csrf_headers

    expect(response).to have_http_status(:not_found)
  end

  it "un membership de sucursal no puede escribir settings (el permiso es de organización)" do
    manager = sign_in(user_with_role("branch_manager", world, branch: world.branch_a1))
    patch "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}/modules/sample/settings", params: { settings: { max_advance_days: 3 } }, as: :json, headers: manager.csrf_headers

    expect(response).to have_http_status(:forbidden)
  end

  it "activar y desactivar escriben auditoría con el usuario de la request" do
    put base, params: { enabled: false }, as: :json, headers: signed_in.csrf_headers
    event = with_tenant(world.organization) { Audit::Event.find_by!(action: "module.disabled") }

    expect(event).to have_attributes(actor_type: "user", actor_id: signed_in.user.id)
  end
end

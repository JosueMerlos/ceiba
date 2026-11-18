require "rails_helper"

# Idempotency of creating a branch: a repeated Idempotency-Key replays the stored response and never creates a second branch.
RSpec.describe "Alta de sucursales: Idempotency-Key" do
  let(:world) { build_access_world }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let!(:signed_in) { sign_in(manager) }
  let(:base) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches" }
  let(:body) { { name: "Sucursal Masaya", time_zone: "America/Managua" } }

  def count = with_tenant(world.organization) { Tenancy::Directory.branches.where(company_id: world.company_a.id, name: "Sucursal Masaya").count }

  def create_branch(user_headers: signed_in.csrf_headers, headers: {})
    post base, params: body, headers: user_headers.merge(headers), as: :json
  end

  it "repetir la petición con la misma clave devuelve la misma respuesta y crea una sola sucursal", :aggregate_failures do
    key = SecureRandom.uuid

    create_branch(headers: { "Idempotency-Key" => key })
    first = [ response.status, response.body ]
    create_branch(headers: { "Idempotency-Key" => key })

    expect(first.first).to eq(201)
    expect([ response.status, response.body ]).to eq(first)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(count).to eq(1)
  end

  it "una clave distinta crea otra sucursal" do
    create_branch(headers: { "Idempotency-Key" => SecureRandom.uuid })
    create_branch(headers: { "Idempotency-Key" => SecureRandom.uuid })

    expect(count).to eq(2)
  end

  it "una repetición con la misma clave responde 403 si al usuario ya le quitaron el permiso", :aggregate_failures do
    writer = user_with_custom_role(world, scope_level: "company", company: world.company_a, permissions: %w[platform.branch.create])
    csrf = sign_in(writer).csrf_headers
    key = SecureRandom.uuid
    create_branch(user_headers: csrf, headers: { "Idempotency-Key" => key })
    expect(response).to have_http_status(:created)
    Access::RolePermission.where(permission_key: "platform.branch.create").delete_all

    create_branch(user_headers: csrf, headers: { "Idempotency-Key" => key })

    expect(response).to have_http_status(:forbidden)
    expect(count).to eq(1)
  end
end

require "rails_helper"

# Hook after_provision de access: el dueño de la organización recibe el membership org_owner EN LA MISMA transacción de la
# provisión. Los datos del dueño llegan en `extras: { owner: }` (Tenancy no los interpreta).
RSpec.describe "Provisión de una organización con dueño", type: :request do
  let(:owner) { Identity::ProvisionUser.call(email: "dueno@ceiba.test", full_name: "Rosa Mendoza", password: "contraseña-segura-1") }
  let(:params) do
    {
      organization: { name: "Barbería S.A." },
      company: { name: "Barbería", slug: "barberia-owner-hook", business_type: "barbershop", currency: "NIO" },
      branch: { name: "Centro", time_zone: "America/Managua" }
    }
  end

  def owner_roles(result)
    with_tenant(result.organization) { Access::Membership.where(user_id: owner.id).includes(:role).map { |m| m.role.key } }
  end

  it "crea el membership org_owner del dueño" do
    result = Tenancy::ProvisionOrganization.call(**params, extras: { owner: })

    expect(owner_roles(result)).to eq([ "org_owner" ])
  end

  it "el dueño puede leer su organización por la API" do
    result = Tenancy::ProvisionOrganization.call(**params, extras: { owner: })
    sign_in(Identity::User.find(owner.id), password: "contraseña-segura-1")

    get "/api/v1/organizations/#{result.organization.id}"

    expect(response).to have_http_status(:ok)
  end

  it "sin dueño la organización se crea igual, sin ningún membership (invitación pendiente: M4.01)" do
    result = Tenancy::ProvisionOrganization.call(**params)

    expect(with_tenant(result.organization) { Access::Membership.count }).to eq(0)
  end

  it "un dueño que no es un usuario de identity revierte TODA la provisión" do
    expect { Tenancy::ProvisionOrganization.call(**params, extras: { owner: { email: "x@y.z" } }) }.to raise_error(ArgumentError, /owner/)
    expect(Tenancy::Organization.where(name: "Barbería S.A.")).to be_empty
  end

  it "el hook está registrado una sola vez, con clave (idempotente en cada recarga)" do
    entries = Rails.application.config.x.tenancy.after_provision_hooks.map(&:first)

    expect(entries.count(:access_owner)).to eq(1)
  end
end

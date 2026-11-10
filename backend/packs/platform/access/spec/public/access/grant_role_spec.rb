require "rails_helper"

RSpec.describe Access::GrantRole do
  let(:world) { build_access_world }
  let(:organization) { world.organization }
  let(:user) { Identity::ProvisionUser.call(email: "ana@ceiba.test", full_name: "Ana", password: "contraseña-segura-1") }

  def memberships_of(user_id)
    with_tenant(organization) { Access::Membership.where(user_id:).includes(:role).map { |m| [ m.role.key, m.company_id, m.branch_id ] } }
  end

  it "concede un rol de organización" do
    described_class.call(user:, role_key: "org_admin", organization:)

    expect(memberships_of(user.id)).to eq([ [ "org_admin", nil, nil ] ])
  end

  it "concede un rol de empresa y uno de sucursal (la empresa se deduce de la sucursal)" do
    described_class.call(user:, role_key: "company_manager", organization:, company: world.company_a)
    described_class.call(user:, role_key: "receptionist", organization:, branch: world.branch_a1)

    expect(memberships_of(user.id)).to contain_exactly(
      [ "company_manager", world.company_a.id, nil ], [ "receptionist", world.company_a.id, world.branch_a1.id ]
    )
  end

  it "es idempotente: repetir la concesión no duplica ni falla" do
    2.times { described_class.call(user:, role_key: "branch_manager", organization:, branch: world.branch_a1) }

    expect(memberships_of(user.id).size).to eq(1)
  end

  it "el usuario obtiene de verdad los permisos del rol" do
    described_class.call(user:, role_key: "company_manager", organization:, company: world.company_a)
    principal = access_principal_for(user, organization)

    expect(principal.can?("platform.branch.create", Access::Scope.company(organization_id: organization.id, company_id: world.company_a.id))).to be(true)
    expect(principal.can?("platform.company.update", Access::Scope.company(organization_id: organization.id, company_id: world.company_a.id))).to be(false)
  end

  it "rechaza un rol que no existe" do
    expect { described_class.call(user:, role_key: "rey", organization:) }.to raise_error(ArgumentError, /rey/)
  end

  it "rechaza un alcance que no corresponde al rol" do
    expect { described_class.call(user:, role_key: "org_admin", organization:, company: world.company_a) }.to raise_error(ArgumentError, /alcance/)
    expect { described_class.call(user:, role_key: "company_manager", organization:) }.to raise_error(ArgumentError, /alcance/)
    expect { described_class.call(user:, role_key: "receptionist", organization:, company: world.company_a) }.to raise_error(ArgumentError, /alcance/)
  end

  it "rechaza una empresa o sucursal de OTRA organización" do
    other = build_access_world

    expect { described_class.call(user:, role_key: "company_manager", organization:, company: other.company_a) }.to raise_error(ArgumentError, /organización/)
    expect { described_class.call(user:, role_key: "receptionist", organization:, branch: other.branch_a1) }.to raise_error(ArgumentError, /organización/)
  end
end

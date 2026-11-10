require "rails_helper"

# Every decision comes from can?(permission, scope), never from a role name.
RSpec.describe "Policies de organización, empresa y sucursal" do
  let(:world) { build_access_world }
  let(:organization) { world.organization }

  def policy(klass, user, record) = klass.new(access_principal_for(user, organization), record)

  def scope_of(klass, user, relation)
    principal = access_principal_for(user, organization)
    with_tenant(organization) { klass::Scope.new(principal, relation).resolve.to_a }
  end

  describe Access::OrganizationPolicy do
    it "org_admin ve y puede leer la organización; branch_manager no (la ve en su lista, pero no su detalle)" do
      admin = user_with_role("org_admin", world)
      manager = user_with_role("branch_manager", world, branch: world.branch_a1)

      expect(policy(described_class, admin, organization).show?).to be(true)
      expect(policy(described_class, manager, organization).show?).to be(false)
    end

    it "crear una organización nunca se autoriza aquí (la provisión es el único camino); editar y borrar siguen la matriz" do
      owner = user_with_role("org_owner", world)
      admin = user_with_role("org_admin", world)

      expect(policy(described_class, owner, organization).create?).to be(false)
      expect([ policy(described_class, owner, organization).update?, policy(described_class, admin, organization).update? ]).to all(be(true))
      expect(policy(described_class, owner, organization).destroy?).to be(true)
      expect(policy(described_class, admin, organization).destroy?).to be(false)
    end

    it "el Scope lista solo las organizaciones donde el usuario tiene membership" do
      other = create(:organization)
      user = user_with_role("receptionist", world, branch: world.branch_a1)
      user_with_role("org_admin", other, user:)

      expect(scope_of(described_class, user, Tenancy::Directory.organizations_for([]))).to contain_exactly(organization, other)
    end

    it "un principal que no es un usuario no lista organizaciones" do
      expect(described_class.new(Access::Principal::ApiKey.new, organization).index?).to be(false)
    end
  end

  describe Access::CompanyPolicy do
    it "branch_manager, receptionist y professional leen la empresa de su sucursal (solo lectura) y no la otra" do
      %w[branch_manager receptionist professional].each do |role|
        user = user_with_role(role, world, branch: world.branch_a1)

        expect(policy(described_class, user, world.company_a).show?).to be(true)
        expect(policy(described_class, user, world.company_b).show?).to be(false)
        expect([ policy(described_class, user, world.company_a).update?, policy(described_class, user, world.company_a).create? ]).to all(be(false))
      end
    end

    it "company_manager lee SU empresa y no la otra" do
      manager = user_with_role("company_manager", world, company: world.company_a)

      expect(policy(described_class, manager, world.company_a).show?).to be(true)
      expect(policy(described_class, manager, world.company_b).show?).to be(false)
    end

    it "company_manager no puede editar ni crear empresas (solo 'ver la suya')" do
      manager = user_with_role("company_manager", world, company: world.company_a)
      subject_policy = policy(described_class, manager, world.company_a)

      expect([ subject_policy.update?, subject_policy.create? ]).to all(be(false))
    end

    it "el Scope de un company_manager contiene solo su empresa; el de org_admin, todas" do
      manager = user_with_role("company_manager", world, company: world.company_a)
      admin = user_with_role("org_admin", world)
      companies = with_tenant(organization) { Tenancy::Directory.companies }

      expect(scope_of(described_class, manager, companies)).to contain_exactly(world.company_a)
      expect(scope_of(described_class, admin, companies)).to contain_exactly(world.company_a, world.company_b)
    end
  end

  describe Access::BranchPolicy do
    it "branch_manager lee su sucursal y no la hermana" do
      manager = user_with_role("branch_manager", world, branch: world.branch_a1)

      expect(policy(described_class, manager, world.branch_a1).show?).to be(true)
      expect(policy(described_class, manager, world.branch_a2).show?).to be(false)
    end

    it "todo rol de sucursal lee SU sucursal (datos básicos) y no las hermanas; no la edita" do
      %w[branch_manager receptionist professional].each do |role|
        user = user_with_role(role, world, branch: world.branch_a1)

        expect(policy(described_class, user, world.branch_a1).show?).to be(true)
        expect(policy(described_class, user, world.branch_a2).show?).to be(false)
        expect(policy(described_class, user, world.branch_a1).update?).to be(false)
      end
    end

    it "el Scope de un company_manager de A contiene A1 y A2 y ninguna de B (criterio 2)" do
      manager = user_with_role("company_manager", world, company: world.company_a)
      branches = with_tenant(organization) { Tenancy::Directory.branches }

      expect(scope_of(described_class, manager, branches)).to contain_exactly(world.branch_a1, world.branch_a2)
    end

    it "el Scope de un branch_manager contiene solo su sucursal" do
      manager = user_with_role("branch_manager", world, branch: world.branch_a1)
      branches = with_tenant(organization) { Tenancy::Directory.branches }

      expect(scope_of(described_class, manager, branches)).to contain_exactly(world.branch_a1)
    end

    it "crear y editar sucursales: company_manager sí (de su empresa), branch_manager no" do
      company_manager = user_with_role("company_manager", world, company: world.company_a)
      branch_manager = user_with_role("branch_manager", world, branch: world.branch_a1)

      expect(policy(described_class, company_manager, world.branch_a2).update?).to be(true)
      expect(policy(described_class, company_manager, world.branch_b1).update?).to be(false)
      expect(policy(described_class, branch_manager, world.branch_a1).update?).to be(false)
    end
  end
end

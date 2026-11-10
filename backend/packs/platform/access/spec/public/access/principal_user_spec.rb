require "rails_helper"

# The effective permission is the UNION of the permissions of all the user's memberships in the active organization whose
# scope CONTAINS the resource (org > company > branch). One query per request, memoized.
RSpec.describe Access::Principal::User do
  let(:organization) { create(:organization) }
  let(:company_a) { create_in(organization, :company) }
  let(:company_b) { create_in(organization, :company) }
  let(:branch_a1) { create_in(organization, :branch, company: company_a) }
  let(:branch_a2) { create_in(organization, :branch, company: company_a) }
  let(:branch_b1) { create_in(organization, :branch, company: company_b) }
  let(:user) { create(:user) }
  let(:permission) { "platform.branch.read" }

  # Test roles with ONE permission and the requested scope: coverage semantics do not depend on the seeded matrix.
  def role_with(permission_key, scope_level)
    role = create(:role, scope_level:)
    Access::RolePermission.create!(role:, permission_key:)
    role
  end

  def grant(role, company: nil, branch: nil, for_user: user, org: organization)
    with_tenant(org) do
      create(:membership, user_id: for_user.id, role:, company_id: company&.id, branch_id: branch&.id)
    end
  end

  def principal_for(target = user, org: organization)
    [ branch_a1, branch_a2, branch_b1 ] # the tree exists BEFORE activating (so companies' branches are preloaded)
    described_class.new(Identity::Principal::User.new(id: target.id, email: target.email, full_name: target.full_name)).tap do |principal|
      with_tenant(org) { principal.activate!(org.id) }
    end
  end

  def org_scope(org = organization) = Access::Scope.organization(org.id)
  def company_scope(company, org = organization) = Access::Scope.company(organization_id: org.id, company_id: company.id)

  def branch_scope(branch, org = organization)
    Access::Scope.branch(organization_id: org.id, company_id: branch.company_id, branch_id: branch.id)
  end

  describe "cobertura jerárquica" do
    it "un membership de organización cubre la organización, todas sus empresas y todas sus sucursales" do
      grant(role_with(permission, "organization"))
      principal = principal_for

      expect([ org_scope, company_scope(company_a), company_scope(company_b), branch_scope(branch_a1), branch_scope(branch_b1) ])
        .to all(satisfy { |scope| principal.can?(permission, scope) })
    end

    it "un membership de empresa cubre esa empresa y sus sucursales, y nada más" do
      grant(role_with(permission, "company"), company: company_a)
      principal = principal_for

      expect(principal.can?(permission, company_scope(company_a))).to be(true)
      expect(principal.can?(permission, branch_scope(branch_a1))).to be(true)
      expect(principal.can?(permission, branch_scope(branch_a2))).to be(true)
      expect(principal.can?(permission, company_scope(company_b))).to be(false)
      expect(principal.can?(permission, branch_scope(branch_b1))).to be(false)
      expect(principal.can?(permission, org_scope)).to be(false)
    end

    it "un membership de sucursal cubre solo esa sucursal" do
      grant(role_with(permission, "branch"), company: company_a, branch: branch_a1)
      principal = principal_for

      expect(principal.can?(permission, branch_scope(branch_a1))).to be(true)
      expect(principal.can?(permission, branch_scope(branch_a2))).to be(false)
      expect(principal.can?(permission, company_scope(company_a))).to be(false)
      expect(principal.can?(permission, branch_scope(branch_b1))).to be(false)
      expect(principal.can?(permission, org_scope)).to be(false)
    end

    it "es la unión de los memberships: cada uno aporta sus permisos en su alcance" do
      grant(role_with("platform.branch.read", "branch"), company: company_a, branch: branch_a1)
      grant(role_with("platform.company.read", "company"), company: company_b)
      principal = principal_for

      expect(principal.can?("platform.branch.read", branch_scope(branch_a1))).to be(true)
      expect(principal.can?("platform.company.read", company_scope(company_b))).to be(true)
      expect(principal.can?("platform.company.read", branch_scope(branch_b1))).to be(true)
      expect(principal.can?("platform.company.read", branch_scope(branch_a1))).to be(false)
      expect(principal.can?("platform.branch.read", branch_scope(branch_b1))).to be(false)
    end

    it "un permiso que el rol no tiene se niega aunque el alcance cubra el recurso" do
      grant(role_with("platform.company.read", "organization"))

      expect(principal_for.can?("platform.company.update", company_scope(company_a))).to be(false)
    end

    it "sin ningún membership se niega todo" do
      expect(principal_for.can?(permission, branch_scope(branch_a1))).to be(false)
    end
  end

  describe "un alcance de sucursal con la empresa equivocada (sonda)" do
    it "company_manager de A NO obtiene permisos sobre la sucursal B1 aunque el Scope diga company_id: A" do
      grant(role_with(permission, "company"), company: company_a)
      principal = principal_for
      forged = Access::Scope.branch(organization_id: organization.id, company_id: company_a.id, branch_id: branch_b1.id)

      expect(principal.can?(permission, forged)).to be(false)
      expect(principal.can?(permission, branch_scope(branch_a1))).to be(true)
    end

    it "un membership de sucursal tampoco vale con una empresa distinta de la suya" do
      grant(role_with(permission, "branch"), company: company_a, branch: branch_a1)
      forged = Access::Scope.branch(organization_id: organization.id, company_id: company_b.id, branch_id: branch_a1.id)

      expect(principal_for.can?(permission, forged)).to be(false)
    end

    it "una sucursal creada después de activar (no precargada) se verifica contra la base, una vez, y se memoriza" do
      grant(role_with(permission, "company"), company: company_a)
      principal = principal_for
      late = create_in(organization, :branch, company: company_a)
      scope = branch_scope(late)
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].include?("branches") }

      allowed = with_tenant(organization) do
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { 3.times.map { principal.can?(permission, scope) } }
      end

      expect(allowed).to all(be(true))
      expect(statements.size).to eq(1)
    end
  end

  describe "criterio 4: varias organizaciones" do
    let(:other_organization) { create(:organization) }
    let(:other_company) { create_in(other_organization, :company) }

    it "solo aplican los permisos de la organización activa" do
      grant(role_with(permission, "organization"), org: other_organization)
      grant(role_with("platform.company.read", "company"), company: company_a)
      principal = principal_for(org: organization)

      expect(principal.can?(permission, org_scope(other_organization))).to be(false)
      expect(principal.can?(permission, branch_scope(branch_a1))).to be(false)
      expect(principal.can?("platform.company.read", company_scope(company_a))).to be(true)
    end

    it "un scope de otra organización se niega aunque el id de empresa coincida con uno propio" do
      grant(role_with("platform.company.read", "organization"))

      expect(principal_for.can?("platform.company.read", company_scope(other_company, other_organization))).to be(false)
    end

    it "al activar la otra organización aplican SUS permisos y no los de la primera" do
      grant(role_with(permission, "organization"))
      grant(role_with("platform.company.read", "organization"), org: other_organization)
      principal = principal_for(org: other_organization)

      expect(principal.can?("platform.company.read", company_scope(other_company, other_organization))).to be(true)
      expect(principal.can?(permission, org_scope(other_organization))).to be(false)
    end
  end

  describe "antes de activar una organización" do
    it "niega todo (nunca consulta por su cuenta)" do
      principal = described_class.new(Identity::Principal::User.new(id: user.id, email: user.email, full_name: user.full_name))

      expect(principal.can?(permission, org_scope)).to be(false)
      expect(principal.member?).to be(false)
    end
  end

  describe "permisos no registrados" do
    it "lanza Access::UnknownPermission: es un bug del código, no una denegación" do
      expect { principal_for.can?("platform.nada.existe", org_scope) }.to raise_error(Access::UnknownPermission, /platform\.nada\.existe/)
    end
  end

  describe "consultas (sin N+1)" do
    def queries_during(&)
      statements = []
      callback = lambda do |*, payload|
        statements << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(SAVEPOINT|RELEASE|BEGIN|COMMIT|SELECT set_config|SELECT current_setting)/)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
      statements
    end

    it "activar la organización hace UNA consulta y cualquier número de can? no hace ninguna" do
      grant(role_with(permission, "company"), company: company_a)
      grant(role_with("platform.company.read", "branch"), company: company_a, branch: branch_a1)
      grant(role_with("platform.branch.update", "organization"))
      scopes = [ org_scope, company_scope(company_a), branch_scope(branch_a1), branch_scope(branch_a2), branch_scope(branch_b1) ]
      principal = described_class.new(Identity::Principal::User.new(id: user.id, email: user.email, full_name: user.full_name))

      activation = with_tenant(organization) { queries_during { principal.activate!(organization.id) } }
      checks = queries_during { 50.times { scopes.each { |scope| principal.can?(permission, scope) } } }

      expect(activation.size).to eq(1)
      expect(activation.first).to include("memberships").and include("role_permissions")
      expect(checks).to be_empty
    end
  end

  describe "visibilidad (qué rutas se ven, antes de preguntar por permisos)" do
    it "un membership de sucursal hace visible su sucursal y su empresa, no las hermanas ni otras empresas" do
      grant(role_with(permission, "branch"), company: company_a, branch: branch_a1)
      principal = principal_for

      expect(principal.member?).to be(true)
      expect(principal.sees_company?(company_a.id)).to be(true)
      expect(principal.sees_branch?(branch_a1.id, company_a.id)).to be(true)
      expect(principal.sees_branch?(branch_a2.id, company_a.id)).to be(false)
      expect(principal.sees_company?(company_b.id)).to be(false)
    end

    it "un membership de empresa hace visibles todas sus sucursales; uno de organización, todo" do
      grant(role_with(permission, "company"), company: company_a)
      owner = create(:user)
      grant(role_with(permission, "organization"), for_user: owner)
      company_principal = principal_for
      org_principal = principal_for(owner)

      expect(company_principal.sees_branch?(branch_a2.id, company_a.id)).to be(true)
      expect(company_principal.sees_company?(company_b.id)).to be(false)
      expect(org_principal.sees_company?(company_b.id)).to be(true)
      expect(org_principal.sees_branch?(branch_b1.id, company_b.id)).to be(true)
    end

    it "un membership sin permisos sigue siendo un membership (es miembro)" do
      grant(create(:role, scope_level: "organization"))

      expect(principal_for.member?).to be(true)
    end
  end

  describe "#reach: a qué recursos llega un permiso (para los Scope de las policies)" do
    it "organización => todo; empresa => esas empresas; sucursal => esas sucursales" do
      grant(role_with(permission, "company"), company: company_a)
      grant(role_with(permission, "branch"), company: company_b, branch: branch_b1)
      reach = principal_for.reach(permission)

      expect(reach).to have_attributes(organization?: false, company_ids: [ company_a.id ], branch_ids: [ branch_b1.id ])
      expect(reach.none?).to be(false)
    end

    it "con un membership de organización alcanza toda la organización" do
      grant(role_with(permission, "organization"))

      expect(principal_for.reach(permission).organization?).to be(true)
    end

    it "sin el permiso no alcanza nada" do
      grant(role_with("platform.company.read", "organization"))

      expect(principal_for.reach(permission).none?).to be(true)
    end
  end

  describe "#organization_ids (selector de contexto, ADR-0028)" do
    it "devuelve las organizaciones donde el usuario tiene algún membership, sin tenant activo" do
      other_organization = create(:organization)
      create(:organization)
      grant(role_with(permission, "organization"))
      grant(role_with(permission, "organization"), org: other_organization)

      expect(principal_for.organization_ids).to contain_exactly(organization.id, other_organization.id)
    end

    it "no incluye las de otros usuarios" do
      grant(role_with(permission, "organization"), for_user: create(:user))

      expect(principal_for.organization_ids).to be_empty
    end
  end
end

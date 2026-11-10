require "rails_helper"

# AUTHORIZATION MATRIX HARNESS: role x scope x resource x action -> allowed/denied, with the PLATFORM part of the role
# matrix copied here BY HAND as a case table independent of the seed. It FAILS if the seed (role_permissions) or the
# engine diverge from the table. Three layers:
#   1. DATA: each system role's platform permissions in the DB == the matrix.
#   2. ENGINE: can?(permission, scope) for 6 roles x permissions x {organization, own/foreign company, own/sibling/foreign branch}.
#   3. HTTP: 6 roles x {own/foreign company} x {own/sibling/foreign branch} against the real API (404 vs 403 vs 200).
module AuthorizationMatrix
  ROLES = %w[org_owner org_admin company_manager branch_manager receptionist professional].freeze
  # Permission => roles that receive it (platform rows of the role matrix).
  MATRIX = {
    "platform.organization.read" => %w[org_owner org_admin],
    "platform.organization.update" => %w[org_owner org_admin],
    "platform.organization.manage_billing" => %w[org_owner],
    "platform.organization.delete" => %w[org_owner],
    "platform.organization.transfer_ownership" => %w[org_owner],
    # Product decision: every role with a membership READS the company and branch it belongs to (basic data).
    "platform.company.read" => %w[org_owner org_admin company_manager branch_manager receptionist professional],
    "platform.company.create" => %w[org_owner org_admin],
    "platform.company.update" => %w[org_owner org_admin],
    "platform.branch.read" => %w[org_owner org_admin company_manager branch_manager receptionist professional],
    "platform.branch.create" => %w[org_owner org_admin company_manager],
    "platform.branch.update" => %w[org_owner org_admin company_manager],
    "platform.company_module.manage" => %w[org_owner org_admin],
    "platform.branding.update" => %w[org_admin company_manager],
    "platform.user.invite" => %w[org_owner org_admin company_manager branch_manager],
    "platform.api_key.manage" => %w[org_owner org_admin],
    "platform.reports.consolidated" => %w[org_owner org_admin]
  }.freeze
  # Scopes each role COVERS in the test world: org_* the whole organization; company_manager of A, A and its branches;
  # branch roles only A1 (org > company > branch).
  TARGETS = %i[organization company_a company_b branch_a1 branch_a2 branch_b1].freeze
  # READ permissions a branch membership also exercises on that branch's company (never on sibling branches).
  UPWARD = %w[platform.company.read].freeze
  REACH = {
    "org_owner" => TARGETS, "org_admin" => TARGETS,
    "company_manager" => %i[company_a branch_a1 branch_a2],
    "branch_manager" => %i[branch_a1], "receptionist" => %i[branch_a1], "professional" => %i[branch_a1]
  }.freeze
  # Expected HTTP status per target: [company A (own), company B (foreign), branch A1 (own), A2 (sibling), B1 (foreign)]
  EXPECTED = {
    "org_owner" => [ 200, 200, 200, 200, 200 ],
    "org_admin" => [ 200, 200, 200, 200, 200 ],
    "company_manager" => [ 200, 404, 200, 200, 404 ],
    "branch_manager" => [ 200, 404, 200, 404, 404 ],
    "receptionist" => [ 200, 404, 200, 404, 404 ],
    "professional" => [ 200, 404, 200, 404, 404 ]
  }.freeze

  # GET /organizations/:id (platform.organization.read: only owner and admin)
  ORGANIZATION_SHOW = {
    "org_owner" => 200, "org_admin" => 200, "company_manager" => 403, "branch_manager" => 403, "receptionist" => 403, "professional" => 403
  }.freeze

  # Listing contents: [companies of GET .../companies, branches of .../companies/A/branches, branches of .../companies/B/branches]
  # (a number = that response, e.g. 404 if the route is not visible to the role).
  INDEXES = {
    "org_owner" => [ %i[company_a company_b], %i[branch_a1 branch_a2], %i[branch_b1] ],
    "org_admin" => [ %i[company_a company_b], %i[branch_a1 branch_a2], %i[branch_b1] ],
    "company_manager" => [ %i[company_a], %i[branch_a1 branch_a2], 404 ],
    "branch_manager" => [ %i[company_a], %i[branch_a1], 404 ],
    "receptionist" => [ %i[company_a], %i[branch_a1], 404 ],
    "professional" => [ %i[company_a], %i[branch_a1], 404 ]
  }.freeze
end

RSpec.describe "Matriz de autorización", type: :request do
  let(:world) { build_access_world }
  let(:organization) { world.organization }

  def member_of(role_key)
    case role_key
    when "company_manager" then user_with_role(role_key, world, company: world.company_a)
    when "branch_manager", "receptionist", "professional" then user_with_role(role_key, world, branch: world.branch_a1)
    else user_with_role(role_key, world)
    end
  end

  def world_id(target) = world.public_send(target).id

  def reaches?(role_key, permission, target)
    reach = AuthorizationMatrix::REACH.fetch(role_key)
    reach += %i[company_a] if AuthorizationMatrix::UPWARD.include?(permission) && Access::SYSTEM_ROLES.fetch(role_key) == "branch"
    reach.include?(target)
  end

  def scope_for(target)
    ids = { organization_id: organization.id }
    case target
    when :organization then Access::Scope.organization(organization.id)
    when :company_a then Access::Scope.company(**ids, company_id: world.company_a.id)
    when :company_b then Access::Scope.company(**ids, company_id: world.company_b.id)
    else
      branch = world.public_send(target)
      Access::Scope.branch(**ids, company_id: branch.company_id, branch_id: branch.id)
    end
  end

  describe "1. los datos sembrados coinciden con la matriz" do
    it "cada rol de sistema tiene EXACTAMENTE los permisos de plataforma que la matriz le da" do
      AuthorizationMatrix::ROLES.each do |role_key|
        expected = AuthorizationMatrix::MATRIX.select { |_permission, roles| roles.include?(role_key) }.keys.sort
        actual = Access::Role.find_by!(key: role_key).role_permissions.where("permission_key LIKE 'platform.%'").pluck(:permission_key).sort

        expect(actual).to eq(expected), "#{role_key}: sobran #{(actual - expected).inspect}, faltan #{(expected - actual).inspect}"
      end
    end

    it "no hay permisos de plataforma registrados que la matriz no conozca" do
      expect(Access.permission_keys.grep(/\Aplatform\./)).to match_array(AuthorizationMatrix::MATRIX.keys)
    end

    it "cada rol tiene el alcance que dice el catálogo" do
      expect(Access::SYSTEM_ROLES).to eq(
        "org_owner" => "organization", "org_admin" => "organization", "company_manager" => "company",
        "branch_manager" => "branch", "receptionist" => "branch", "professional" => "branch"
      )
    end
  end

  describe "2. motor: can?(permiso, alcance) para cada rol" do
    AuthorizationMatrix::ROLES.each do |role_key|
      it "#{role_key}: permitido solo si el rol tiene el permiso Y su alcance cubre el recurso" do
        principal = access_principal_for(member_of(role_key), organization)

        mismatches = AuthorizationMatrix::MATRIX.flat_map do |permission, roles|
          AuthorizationMatrix::TARGETS.filter_map do |target|
            expected = roles.include?(role_key) && reaches?(role_key, permission, target)
            actual = principal.can?(permission, scope_for(target))
            "#{role_key} #{permission} @#{target}: esperado #{expected}, fue #{actual}" unless actual == expected
          end
        end

        expect(mismatches).to be_empty
      end
    end

    it "un usuario sin ningún membership no puede nada, en ningún alcance" do
      principal = access_principal_for(create(:user), organization)

      expect(AuthorizationMatrix::MATRIX.keys.product(AuthorizationMatrix::TARGETS).map { |permission, target| principal.can?(permission, scope_for(target)) }).to all(be(false))
    end
  end

  describe "3. HTTP: empresa propia/ajena × sucursal propia/hermana/ajena" do
    def paths
      base = "/api/v1/organizations/#{organization.id}/companies"
      [
        "#{base}/#{world.company_a.id}", "#{base}/#{world.company_b.id}",
        "#{base}/#{world.company_a.id}/branches/#{world.branch_a1.id}",
        "#{base}/#{world.company_a.id}/branches/#{world.branch_a2.id}",
        "#{base}/#{world.company_b.id}/branches/#{world.branch_b1.id}"
      ]
    end

    AuthorizationMatrix::ROLES.each do |role_key|
      it "#{role_key} recibe #{AuthorizationMatrix::EXPECTED.fetch(role_key).inspect}" do
        sign_in(member_of(role_key))

        statuses = paths.map do |path|
          get path
          response.status
        end

        expect(statuses).to eq(AuthorizationMatrix::EXPECTED.fetch(role_key))
      end
    end

    it "GET /organizations/:id solo lo leen owner y admin; el resto es 403 (visible, sin permiso)" do
      statuses = AuthorizationMatrix::ROLES.to_h do |role_key|
        sign_in(member_of(role_key))
        get "/api/v1/organizations/#{organization.id}"
        [ role_key, response.status ]
      end

      expect(statuses).to eq(AuthorizationMatrix::ORGANIZATION_SHOW)
    end

    AuthorizationMatrix::ROLES.each do |role_key|
      it "#{role_key}: los listados devuelven solo lo que su alcance contiene" do
        sign_in(member_of(role_key))
        base = "/api/v1/organizations/#{organization.id}/companies"
        urls = [ base, "#{base}/#{world.company_a.id}/branches", "#{base}/#{world.company_b.id}/branches" ]

        actual = urls.map do |url|
          get url
          response.status == 200 ? response.parsed_body["data"].pluck("id").sort : response.status
        end

        expect(actual).to eq(AuthorizationMatrix::INDEXES.fetch(role_key).map { |expected| expected.is_a?(Array) ? expected.map { |target| world_id(target) }.sort : expected })
      end
    end

    it "un usuario de OTRA organización recibe 404 en todo, y su lista de organizaciones es solo la suya" do
      other = build_access_world
      sign_in(user_with_role("org_owner", other))

      statuses = [ "", "/companies", "/companies/#{world.company_a.id}", "/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}" ].map do |suffix|
        get "/api/v1/organizations/#{organization.id}#{suffix}"
        response.status
      end
      get "/api/v1/organizations"

      expect(statuses).to all(eq(404))
      expect(response.parsed_body["data"].pluck("id")).to eq([ other.organization.id ])
    end

    it "ningún 404 distingue 'no existe' de 'existe pero no es tuyo'" do
      sign_in(member_of("branch_manager"))
      get paths[3] # A2: exists, sibling
      sibling = response.parsed_body.except("request_id", "instance")
      get "#{paths[2].sub(world.branch_a1.id, '0198f0a0-0000-7000-8000-000000000000')}" # inexistente
      missing = response.parsed_body.except("request_id", "instance")

      expect(sibling).to eq(missing)
    end
  end
end

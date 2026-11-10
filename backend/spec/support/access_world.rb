# An access control "world" for specs: ONE organization with two companies (A and B) and their branches (A1, A2 in A; B1
# in B), and users with a system role in a scope. It is the basis of the route, policy and matrix specs.
#
#   world = build_access_world
#   user  = user_with_role("branch_manager", world, branch: world.branch_a1)
module AccessWorld
  World = Struct.new(:organization, :company_a, :company_b, :branch_a1, :branch_a2, :branch_b1, keyword_init: true)

  def build_access_world(organization: create(:organization))
    company_a = create_in(organization, :company)
    company_b = create_in(organization, :company)
    World.new(
      organization:, company_a:, company_b:,
      branch_a1: create_in(organization, :branch, company: company_a),
      branch_a2: create_in(organization, :branch, company: company_a),
      branch_b1: create_in(organization, :branch, company: company_b)
    )
  end

  # Creates a user and grants `role_key` in the given scope (organization by default). The scope MUST match the system
  # role's (the database requires it). `user:` adds a second membership to the same user.
  def user_with_role(role_key, world_or_organization, company: nil, branch: nil, user: create(:user))
    organization = world_or_organization.respond_to?(:organization) ? world_or_organization.organization : world_or_organization
    with_tenant(organization) do
      create(:membership, user_id: user.id, role_key:, company_id: company&.id || branch&.company_id, branch_id: branch&.id)
    end
    user
  end

  # A user with a TEST role (not a system one) with exactly the given permissions, in the given scope. Exercises the 403
  # ("visible but not allowed") without depending on the system roles matrix.
  def user_with_custom_role(world, scope_level:, permissions: [], company: nil, branch: nil)
    role = create(:role, scope_level:)
    permissions.each { |key| Access::RolePermission.create!(role:, permission_key: key) }
    user = create(:user)
    with_tenant(world.organization) do
      create(:membership, user_id: user.id, role:, company_id: company&.id || branch&.company_id, branch_id: branch&.id)
    end
    user
  end

  def access_principal_for(user, organization)
    principal = Access::Principal::User.new(Identity::Principal::User.new(id: user.id, email: user.email, full_name: user.full_name))
    with_tenant(organization) { principal.activate!(organization.id) }
    principal
  end
end

RSpec.configure { |config| config.include AccessWorld }

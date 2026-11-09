# Un "mundo" de control de acceso para los specs: UNA organización con dos empresas (A y B) y sus sucursales (A1, A2 en A; B1
# en B), y usuarios con un rol de sistema en un alcance. Es la base de los specs de rutas, policies y de la matriz.
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

  # Crea un usuario y le concede `role_key` en el alcance dado (organización por defecto). El alcance DEBE coincidir con el
  # del rol de sistema (la base lo exige). `user:` permite sumar un segundo membership al mismo usuario.
  def user_with_role(role_key, world_or_organization, company: nil, branch: nil, user: create(:user))
    organization = world_or_organization.respond_to?(:organization) ? world_or_organization.organization : world_or_organization
    with_tenant(organization) do
      create(:membership, user_id: user.id, role_key:, company_id: company&.id || branch&.company_id, branch_id: branch&.id)
    end
    user
  end

  # Un usuario con un rol de PRUEBA (no de sistema) con exactamente los permisos dados, en el alcance dado. Sirve para ejercitar el
  # 403 ("visible pero no permitido") sin depender de la matriz de los roles de sistema.
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

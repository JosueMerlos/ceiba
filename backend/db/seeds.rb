# Datos de demo.
# Idempotente: se puede ejecutar cuantas veces haga falta (db:setup, db:seed, reset-db).
#
# Usuario multiorganización (M0.12): ana@multi-org.ceiba.test es org_admin de Barbería El Güegüense y dueña de Café Volcán.
#
# Corre como app_user (config/initializers/seed_role.rb) y crea TODO solo con las APIs públicas de los packs:
# Tenancy::ProvisionOrganization (organización + primera empresa + primera sucursal + el dueño, por el hook de access),
# Tenancy::AddCompany / Tenancy::AddBranch, Identity::ProvisionUser y Access::GrantRole. Nunca toca los modelos directamente:
# el estado inicial de una organización de demo es el mismo que el de un cliente real.
#
# Idempotencia: la identidad de cada grupo es el slug de su primera empresa. Cada grupo se crea en UNA transacción; si el
# slug ya existe, ProvisionOrganization lo dice con Tenancy::ProvisioningFailed(:slug_taken) y el grupo se omite entero.
# LIMITACIÓN: un grupo sembrado ANTES de M0.08 (sin memberships) no se completa al volver a sembrar (no hay una API pública
# para localizar una empresa por slug sin contexto); `make reset-db` recrea la base de desarrollo con todo.

Access.sync!

# Cada grupo: la organización, su dueño (org_owner), las empresas con sus sucursales y el personal con su rol y alcance.
# `staff[].company` es el slug de la empresa; `staff[].branch`, el nombre de la sucursal (solo roles de sucursal).
DEMO_GROUPS = [
  {
    organization: { name: "Barbería El Güegüense", legal_name: "Barbería El Güegüense, S.A." },
    user: { email: "rosa@barberia-guegu.ceiba.test", full_name: "Rosa Mendoza" },
    companies: [
      {
        company: { name: "Barbería El Güegüense", slug: "barberia-guegu", business_type: "barbershop", currency: "NIO" },
        branches: [ { name: "Sucursal Centro", time_zone: "America/Managua" } ]
      }
    ],
    staff: [
      { user: { email: "gerente@barberia-guegu.ceiba.test", full_name: "Mauricio Téllez" }, role: "branch_manager", company: "barberia-guegu", branch: "Sucursal Centro" },
      { user: { email: "recepcion@barberia-guegu.ceiba.test", full_name: "Julia Reyes" }, role: "receptionist", company: "barberia-guegu", branch: "Sucursal Centro" },
      { user: { email: "profesional@barberia-guegu.ceiba.test", full_name: "Don Efraín Blandón" }, role: "professional", company: "barberia-guegu", branch: "Sucursal Centro" },
      # Usuario en DOS organizaciones (ADR-0028, M0.12): org_admin aquí y dueña de "Café Volcán". Prueba el selector de contexto.
      { user: { email: "ana@multi-org.ceiba.test", full_name: "Ana Lacayo" }, role: "org_admin" }
    ]
  },
  {
    organization: { name: "Grupo Salud & Estilo", legal_name: "Grupo Salud & Estilo, S.A." },
    user: { email: "luis@salud-estilo.ceiba.test", full_name: "Luis Ortega" },
    companies: [
      {
        company: { name: "Clínica Dental Sonrisa", slug: "clinica-sonrisa", business_type: "dental", currency: "USD" },
        branches: [ { name: "Clínica Sonrisa Central", time_zone: "America/Managua" } ]
      },
      {
        company: { name: "Salón Estilo", slug: "salon-estilo", business_type: "salon", currency: "NIO" },
        branches: [ { name: "Estilo Centro", time_zone: "America/Managua" }, { name: "Estilo Altamira", time_zone: "America/Managua" } ]
      }
    ],
    staff: [
      { user: { email: "admin@salud-estilo.ceiba.test", full_name: "Elena Cruz" }, role: "org_admin" },
      { user: { email: "marta@salud-estilo.ceiba.test", full_name: "Marta Solís" }, role: "company_manager", company: "salon-estilo" },
      { user: { email: "gerente@salud-estilo.ceiba.test", full_name: "Carlos Navas" }, role: "branch_manager", company: "salon-estilo", branch: "Estilo Altamira" },
      { user: { email: "recepcion@salud-estilo.ceiba.test", full_name: "Lucía Pérez" }, role: "receptionist", company: "salon-estilo", branch: "Estilo Centro" },
      { user: { email: "profesional@salud-estilo.ceiba.test", full_name: "Sandra Gómez" }, role: "professional", company: "salon-estilo", branch: "Estilo Centro" }
    ]
  },
  {
    organization: { name: "Café Volcán", legal_name: "Café Volcán, S.A." },
    user: { email: "ana@multi-org.ceiba.test", full_name: "Ana Lacayo" },
    companies: [
      {
        company: { name: "Café Volcán", slug: "cafe-volcan", business_type: "cafe", currency: "NIO" },
        branches: [ { name: "Sede Granada", time_zone: "America/Managua" } ]
      }
    ],
    staff: []
  }
].freeze

# CONTRASEÑA: la de DESARROLLO es pública y está documentada (docs/architecture/11-security.md): `ceiba-demo-2026`. NUNCA
# se usa en producción ni en staging (RAILS_ENV=production): allí hace falta SEED_DEMO_PASSWORD, y sin ella no se
# siembran usuarios (ni, por tanto, dueños ni personal). Los correos usan el dominio reservado `.test`.
DEMO_PASSWORD_FOR_DEVELOPMENT = "ceiba-demo-2026".freeze

def demo_password
  ENV["SEED_DEMO_PASSWORD"].presence || (DEMO_PASSWORD_FOR_DEVELOPMENT unless Rails.env.production?)
end

# Usuario de demo (idempotente por correo) o nil si no hay contraseña permitida.
def seed_user(attributes)
  password = demo_password
  return unless password

  Identity::ProvisionUser.call(password:, **attributes)
end

# Provisiona la primera empresa del grupo. Devuelve nil si su slug ya existe (el grupo ya estaba sembrado); cualquier
# otro fallo, incluido un slug repetido en una empresa POSTERIOR, se propaga y aborta (no se disfraza de "ya existe").
def provision_first(group, owner)
  first = group.fetch(:companies).first
  extras = owner ? { owner: } : {}
  Tenancy::ProvisionOrganization.call(
    organization: group.fetch(:organization), company: first.fetch(:company), branch: first.fetch(:branches).first, extras:
  )
rescue Tenancy::ProvisioningFailed => error
  raise unless error.code == :slug_taken

  nil
end

# Empresas y sucursales del grupo por slug / nombre, para asignar al personal.
def create_structure(group, result)
  first, *others = group.fetch(:companies)
  companies = { first.dig(:company, :slug) => result.company }
  branches = { first.fetch(:branches).first.fetch(:name) => result.branch }
  first.fetch(:branches).drop(1).each { |branch| branches[branch.fetch(:name)] = Tenancy::AddBranch.call(company: result.company, **branch) }
  others.each do |entry|
    company = Tenancy::AddCompany.call(organization: result.organization, **entry.fetch(:company))
    companies[entry.dig(:company, :slug)] = company
    entry.fetch(:branches).each { |branch| branches[branch.fetch(:name)] = Tenancy::AddBranch.call(company:, **branch) }
  end
  [ companies, branches ]
end

def seed_staff(group, result, companies, branches)
  group.fetch(:staff).each do |member|
    user = seed_user(member.fetch(:user)) or next
    Access::GrantRole.call(
      user:, role_key: member.fetch(:role), organization: result.organization,
      company: companies[member[:company]], branch: branches[member[:branch]]
    )
    puts "Rol listo: #{member.dig(:user, :email)} (#{member.fetch(:role)})"
  end
end

def seed_group(group)
  seeded = false
  owner = seed_user(group.fetch(:user))
  puts(owner ? "Usuario listo: #{group.dig(:user, :email)}" : "Usuario omitido (#{group.dig(:user, :email)}): define SEED_DEMO_PASSWORD para sembrar usuarios en producción")
  ApplicationRecord.transaction do
    result = provision_first(group, owner)
    next unless result

    companies, branches = create_structure(group, result)
    seed_staff(group, result, companies, branches)
    seeded = true
  end
  puts(seeded ? "Sembrada: #{group.dig(:organization, :name)}" : "Ya existe: #{group.dig(:organization, :name)}")
end

DEMO_GROUPS.each { |group| seed_group(group) }

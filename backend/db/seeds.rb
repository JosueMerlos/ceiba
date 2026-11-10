# Demo data. Idempotent: safe to run as often as needed (db:setup, db:seed, reset-db).
#
# Runs as app_user and creates EVERYTHING through the packs' public APIs, never touching models directly, so a demo
# organization starts in the same state as a real customer's.
#
# Idempotency: a group's identity is the slug of its first company. Each group is created in ONE transaction; if the slug
# exists, ProvisionOrganization raises Tenancy::ProvisioningFailed(:slug_taken) and the whole group is skipped.
# LIMITATION: a group seeded before memberships existed is not completed on re-seed (no public API finds a company by
# slug without a context); `make reset-db` rebuilds the development database.

Access.sync!

# `staff[].company` is the company slug; `staff[].branch` is the branch name (branch-level roles only).
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
      # Same user in TWO organizations (org_admin here, owner of "Café Volcán"): exercises the context selector.
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

# The development password is public by design. It is NEVER used in production or staging (RAILS_ENV=production):
# there SEED_DEMO_PASSWORD is required, and without it no users (hence no owners or staff) are seeded.
DEMO_PASSWORD_FOR_DEVELOPMENT = "ceiba-demo-2026".freeze

def demo_password
  ENV["SEED_DEMO_PASSWORD"].presence || (DEMO_PASSWORD_FOR_DEVELOPMENT unless Rails.env.production?)
end

# Idempotent by email; nil when no password is allowed.
def seed_user(attributes)
  password = demo_password
  return unless password

  Identity::ProvisionUser.call(password:, **attributes)
end

# Returns nil if the slug exists (group already seeded); any other failure, including a duplicate slug on a LATER
# company, propagates and aborts instead of being disguised as "already exists".
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

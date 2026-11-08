# Datos de demo. Idempotente: se puede ejecutar cuantas veces haga falta (db:setup, db:seed, reset-db).
#
# Corre como app_user (config/initializers/seed_role.rb) y crea TODO solo con la API pública de tenancy:
# Tenancy::ProvisionOrganization (organización + primera empresa + primera sucursal) y, para las formas más grandes,
# Tenancy::AddCompany / Tenancy::AddBranch. Nunca toca los modelos directamente: el estado inicial de una organización
# de demo es el mismo que el de un cliente real.
#
# Idempotencia: la identidad de cada grupo es el slug de su primera empresa. Cada grupo se crea en UNA transacción; si el
# slug ya existe, ProvisionOrganization lo dice con Tenancy::ProvisioningFailed(:slug_taken) y el grupo se omite entero.

DEMO_GROUPS = [
  {
    organization: { name: "Barbería El Güegüense", legal_name: "Barbería El Güegüense, S.A." },
    companies: [
      {
        company: { name: "Barbería El Güegüense", slug: "barberia-guegu", business_type: "barbershop", currency: "NIO" },
        branches: [ { name: "Sucursal Centro", time_zone: "America/Managua" } ]
      }
    ]
  },
  {
    organization: { name: "Grupo Salud & Estilo", legal_name: "Grupo Salud & Estilo, S.A." },
    companies: [
      {
        company: { name: "Clínica Dental Sonrisa", slug: "clinica-sonrisa", business_type: "dental", currency: "USD" },
        branches: [ { name: "Clínica Sonrisa Central", time_zone: "America/Managua" } ]
      },
      {
        company: { name: "Salón Estilo", slug: "salon-estilo", business_type: "salon", currency: "NIO" },
        branches: [ { name: "Estilo Centro", time_zone: "America/Managua" }, { name: "Estilo Altamira", time_zone: "America/Managua" } ]
      }
    ]
  }
].freeze

# Provisiona la primera empresa del grupo. Devuelve nil si su slug ya existe (el grupo ya estaba sembrado); cualquier
# otro fallo, incluido un slug repetido en una empresa POSTERIOR, se propaga y aborta (no se disfraza de "ya existe").
def provision_first(group)
  first = group.fetch(:companies).first
  Tenancy::ProvisionOrganization.call(organization: group.fetch(:organization), company: first.fetch(:company), branch: first.fetch(:branches).first)
rescue Tenancy::ProvisioningFailed => error
  raise unless error.code == :slug_taken

  nil
end

def seed_group(group)
  first, *others = group.fetch(:companies)
  seeded = false
  ApplicationRecord.transaction do
    result = provision_first(group)
    next unless result

    first.fetch(:branches).drop(1).each { |branch| Tenancy::AddBranch.call(company: result.company, **branch) }
    others.each do |entry|
      company = Tenancy::AddCompany.call(organization: result.organization, **entry.fetch(:company))
      entry.fetch(:branches).each { |branch| Tenancy::AddBranch.call(company:, **branch) }
    end
    seeded = true
  end
  puts(seeded ? "Sembrada: #{group.dig(:organization, :name)}" : "Ya existe: #{group.dig(:organization, :name)}")
end

DEMO_GROUPS.each { |group| seed_group(group) }

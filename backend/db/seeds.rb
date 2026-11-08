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

def seed_group(group)
  first, *others = group.fetch(:companies)
  ApplicationRecord.transaction do
    result = Tenancy::ProvisionOrganization.call(organization: group.fetch(:organization), company: first.fetch(:company), branch: first.fetch(:branches).first)
    first.fetch(:branches).drop(1).each { |branch| Tenancy::AddBranch.call(company: result.company, **branch) }
    others.each do |entry|
      company = Tenancy::AddCompany.call(organization: result.organization, **entry.fetch(:company))
      entry.fetch(:branches).each { |branch| Tenancy::AddBranch.call(company:, **branch) }
    end
  end
  puts "Sembrada: #{group.dig(:organization, :name)}"
rescue Tenancy::ProvisioningFailed => error
  raise unless error.code == :slug_taken

  puts "Ya existe: #{group.dig(:organization, :name)}"
end

DEMO_GROUPS.each { |group| seed_group(group) }

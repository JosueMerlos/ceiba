# Demo hook of the appointments module. Loaded BY PATH from the root db/seeds.rb (the module is invisible to the root pack),
# which calls `seed_company` for every demo company inside its tenancy context (auditing needs one).
#
# Idempotent: a company that already has services is left alone.
module AppointmentsDemoSeeds
  # [name, duration_minutes, price_minor]; prices are in the company's currency (C$ 200 = 20_000, US$ 40 = 4_000).
  CATALOGS = {
    "barbershop" => [
      [ "Corte clásico", 30, 20_000 ],
      [ "Corte y barba", 45, 30_000 ],
      [ "Afeitado clásico", 30, 15_000 ]
    ],
    "dental" => [
      [ "Limpieza dental", 45, 4_000 ],
      [ "Consulta de valoración", 30, 2_500 ],
      [ "Blanqueamiento dental", 60, 12_000 ]
    ],
    "salon" => [
      [ "Corte de dama", 45, 25_000 ],
      [ "Tinte completo", 120, 80_000 ],
      [ "Manicure", 40, 18_000 ],
      [ "Peinado de evento", 60, 35_000 ]
    ]
  }.freeze

  # business type => { branch name => { service name => override attributes } }
  OVERRIDES = {
    "salon" => { "Estilo Altamira" => { "Corte de dama" => { price_minor: 28_000 } } }
  }.freeze

  module_function

  # Seeds the catalog without enabling the module: a demo company without appointments (the salon) is the fixture that
  # proves navigation depends on the company, and its catalog is ready for when the module gets enabled.
  def seed_company(company)
    catalog = CATALOGS[company.business_type] or return
    return if Appointments::Service.exists?(company_id: company.id)

    services = catalog.each_with_index.to_h do |(name, duration_minutes, price_minor), position|
      service = Appointments::Catalog::CreateService.call(
        company_id: company.id, attributes: { name:, duration_minutes:, price_minor:, position: }
      )
      [ name, service ]
    end
    seed_overrides(company, services)
    puts "Catálogo listo: #{company.name} (#{services.size} servicios)"
  end

  def seed_overrides(company, services)
    OVERRIDES.fetch(company.business_type, {}).each do |branch_name, by_service|
      branch = Tenancy::Directory.branches.find_by!(company_id: company.id, name: branch_name)
      by_service.each do |service_name, attributes|
        Appointments::Catalog::UpsertOverride.call(service: services.fetch(service_name), branch_id: branch.id, attributes:)
      end
    end
  end
end

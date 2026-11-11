# Demo hook of the appointments module. Loaded BY PATH from the root db/seeds.rb (the module is invisible to the root pack),
# which calls `seed_company` for every demo company inside its tenancy context (auditing needs one).
#
# Idempotent by section: the catalog is skipped when the company already has services and the staff (professionals,
# resources, hours and an absence) when it already has professionals, so a database seeded before the staff existed gets it
# on the next run without touching what is there.
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

  # business type => professionals. `email` links the record to a demo user through the `people` map (nil without a demo
  # password); `days` are the weekdays they work (0 = Sunday), mornings and afternoons. The same email in two companies is
  # ONE person with two independent records.
  SHARED_PERSON = "profesional@salud-estilo.ceiba.test".freeze
  PROFESSIONALS = {
    "barbershop" => [
      { name: "Don Efraín Blandón", email: "profesional@barberia-guegu.ceiba.test", branch: "Sucursal Centro", days: [ 1, 2, 3, 4, 5, 6 ],
        services: [ "Corte clásico", "Corte y barba", "Afeitado clásico" ] },
      { name: "Ramiro Salinas", branch: "Sucursal Centro", days: [ 2, 3, 4, 5, 6 ], services: [ "Corte clásico", "Afeitado clásico" ] }
    ],
    "dental" => [
      { name: "Sandra Gómez", email: SHARED_PERSON, branch: "Clínica Sonrisa Central", days: [ 2, 4 ], services: [ "Limpieza dental", "Consulta de valoración" ] },
      { name: "Dr. Pablo Quintana", branch: "Clínica Sonrisa Central", days: [ 1, 2, 3, 4, 5 ],
        services: [ "Limpieza dental", "Consulta de valoración", "Blanqueamiento dental" ] }
    ],
    "salon" => [
      { name: "Sandra Gómez", email: SHARED_PERSON, branch: "Estilo Centro", days: [ 1, 3, 5 ], services: [ "Corte de dama", "Manicure", "Peinado de evento" ] },
      { name: "Karla Mendieta", branch: "Estilo Altamira", days: [ 2, 4, 6 ],
        services: [ "Corte de dama", "Tinte completo", "Manicure", "Peinado de evento" ] }
    ]
  }.freeze

  # business type => resources; `days` gives the resource its own hours (08:00-17:00), otherwise it follows the branch's.
  RESOURCES = {
    "barbershop" => [ { branch: "Sucursal Centro", name: "Silla 1", kind: "chair" }, { branch: "Sucursal Centro", name: "Silla 2", kind: "chair" } ],
    "dental" => [
      { branch: "Clínica Sonrisa Central", name: "Sillón 1", kind: "chair" },
      { branch: "Clínica Sonrisa Central", name: "Sala de blanqueamiento", kind: "room", days: [ 1, 2, 3, 4, 5 ] }
    ],
    "salon" => [
      { branch: "Estilo Centro", name: "Sillón 1", kind: "chair" },
      { branch: "Estilo Centro", name: "Sillón 2", kind: "chair" },
      { branch: "Estilo Altamira", name: "Sillón 1", kind: "chair" }
    ]
  }.freeze

  # business type => service name => resource kind the service needs.
  REQUIREMENTS = {
    "barbershop" => { "Corte clásico" => "chair", "Corte y barba" => "chair" },
    "dental" => { "Limpieza dental" => "chair", "Blanqueamiento dental" => "room" },
    "salon" => { "Corte de dama" => "chair", "Tinte completo" => "chair" }
  }.freeze

  SHIFTS = [ %w[09:00 13:00], %w[14:00 18:00] ].freeze
  RESOURCE_SHIFT = %w[08:00 17:00].freeze

  module_function

  # Seeds the demo data of a company: the catalog without enabling the module (a demo company without appointments, the
  # salon, is the fixture that proves navigation depends on the company, and its catalog is ready for when the module gets
  # enabled) and then its staff. `people` maps a demo user's email to its id.
  def seed_company(company, people: {})
    seed_catalog(company)
    seed_staff(company, people)
  end

  def seed_catalog(company)
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

  # Branches without opening hours get the default week here too: the ones added after the module was enabled and the ones
  # of a company without the module never went through the enable hook.
  def seed_staff(company, people)
    professionals = PROFESSIONALS[company.business_type] or return
    return if Appointments::Professional.exists?(company_id: company.id)

    Appointments::Lifecycle::OnEnable.call(company:)
    services = Appointments::Service.where(company_id: company.id).index_by(&:name)
    branches = Tenancy::Directory.branches.where(company_id: company.id).index_by(&:name)

    created = professionals.map { seed_professional(company, it, people, services, branches) }
    seed_resources(company, services, branches)
    seed_time_off(created.first)
    puts "Equipo listo: #{company.name} (#{created.size} profesionales)"
  end

  def seed_professional(company, entry, people, services, branches)
    branch = branches.fetch(entry.fetch(:branch))
    professional = Appointments::Staff::CreateProfessional.call(
      company_id: company.id, attributes: { display_name: entry.fetch(:name), user_id: people[entry[:email]] }
    )
    Appointments::Staff::AssignBranch.call(professional:, branch_id: branch.id)
    Appointments::Staff::SetServices.call(professional:, service_ids: entry.fetch(:services).map { services.fetch(it).id })
    Appointments::Staff::ReplaceSchedule.call(owner: professional, branch_id: branch.id, slots: slots(entry.fetch(:days), SHIFTS))
    professional
  end

  def seed_resources(company, services, branches)
    RESOURCES.fetch(company.business_type, []).each do |entry|
      branch = branches.fetch(entry.fetch(:branch))
      resource = Appointments::Staff::CreateResource.call(
        company_id: company.id, branch_id: branch.id, attributes: entry.slice(:name, :kind)
      )
      next unless entry[:days]

      Appointments::Staff::ReplaceSchedule.call(owner: resource, branch_id: branch.id, slots: slots(entry.fetch(:days), [ RESOURCE_SHIFT ]))
    end
    REQUIREMENTS.fetch(company.business_type, {}).each do |name, kind|
      Appointments::Staff::SetResourceRequirements.call(service: services.fetch(name), kinds: [ kind ])
    end
  end

  # Two weeks from now, so the demo always shows an upcoming absence. Free text, and never health data.
  def seed_time_off(professional)
    starts_at = Time.current.beginning_of_day + 14.days
    Appointments::Staff::CreateTimeOff.call(
      owner: professional, attributes: { starts_at:, ends_at: starts_at + 3.days, reason: "Vacaciones" }
    )
  end

  def slots(days, shifts)
    days.flat_map { |weekday| shifts.map { |starts, ends| { weekday:, starts_at_local: starts, ends_at_local: ends } } }
  end
end

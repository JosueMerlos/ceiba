# A simulated salon week for the internal pilot and for measuring the agenda under load. Loaded BY PATH from the demo:agenda_pilot
# task (the module is invisible to the root pack); never part of db:seed, so the demo fixtures the E2E rely on stay untouched.
# Each run books the current week once: the salon (catalog, staff, chairs, hours) is created the first time and reused after,
# and a week is booked all or nothing, together with the salon when that is new. Must run inside a tenant context.
module AppointmentsPilotSeeds
  # Durations of at most an hour, because each professional's appointments start on the hour.
  SERVICES = [ [ "Corte de dama", 45, 25_000 ], [ "Tinte completo", 60, 80_000 ], [ "Manicure", 30, 18_000 ], [ "Peinado de evento", 60, 35_000 ] ].freeze
  PROFESSIONALS = [ "Rosa Martínez", "Luis Pérez", "Ana Gómez", "Pedro Hernández", "Karla Mendieta" ].freeze
  CUSTOMERS = [ "María José López", "Fernanda Ruiz", "Karla Mendoza", "Sofía Castillo", "Javier Espinoza", "Carlos Téllez", "Ernesto Rivas",
                "Marvin Ortega", "Daniel Chavarría", "Valeria Duarte", "Gabriela Solís", "Andrea Pineda" ].freeze
  # Monday to Saturday.
  WEEKDAYS = (1..6)
  OPENING = [ %w[08:00 18:00] ].freeze
  START_HOURS = [ 8, 9, 10, 11, 13, 14, 15, 16, 17 ].freeze
  SYSTEM_ACTOR = Access::Principal::System.new

  module_function

  def seed(company:, branch:, professional_user_id:)
    zone = ActiveSupport::TimeZone[branch.time_zone]
    monday = Time.current.in_time_zone(zone).to_date.beginning_of_week
    return false if week_booked?(branch, monday.in_time_zone(zone))

    ApplicationRecord.transaction(requires_new: true) do
      services, people = existing_salon(company, branch) || create_salon(company, branch, professional_user_id)
      book_week(company, branch, services, people, create_customers(company), monday, zone)
    end
    true
  end

  def week_booked?(branch, monday) = Appointments::Appointment.where(branch_id: branch.id, starts_at: monday...(monday + 7.days)).exists?

  # UUIDv7 ids keep creation order, so the professionals come back in the order they were seeded.
  def existing_salon(company, branch)
    services = Appointments::Service.where(company_id: company.id).order(:position).to_a
    [ services, Appointments::Professional.assigned_to(branch).order(:id).to_a ] if services.any?
  end

  def create_salon(company, branch, professional_user_id)
    services = create_services(company)
    people = create_professionals(company, branch, services, professional_user_id)
    create_chairs(company, branch, services)
    Appointments::Staff::ReplaceSchedule.call(owner: branch, branch_id: branch.id, slots: slots)
    [ services, people ]
  end

  def create_services(company)
    SERVICES.each_with_index.map do |(name, duration_minutes, price_minor), position|
      Appointments::Catalog::CreateService.call(company_id: company.id, attributes: { name:, duration_minutes:, price_minor:, position: })
    end
  end

  def create_professionals(company, branch, services, professional_user_id)
    PROFESSIONALS.each_with_index.map do |display_name, index|
      user_id = index.zero? ? professional_user_id : nil
      Appointments::Staff::CreateProfessional.call(company_id: company.id, attributes: { display_name:, user_id: }).tap do |professional|
        Appointments::Staff::AssignBranch.call(professional:, branch_id: branch.id)
        Appointments::Staff::SetServices.call(professional:, service_ids: services.map(&:id))
        Appointments::Staff::ReplaceSchedule.call(owner: professional, branch_id: branch.id, slots:)
      end
    end
  end

  def create_chairs(company, branch, services)
    PROFESSIONALS.size.times do |index|
      Appointments::Staff::CreateResource.call(company_id: company.id, branch_id: branch.id, attributes: { name: "Sillón #{index + 1}", kind: "chair" })
    end
    services.each { |service| Appointments::Staff::SetResourceRequirements.call(service:, kinds: [ "chair" ]) }
  end

  # Fake numbers on purpose (+505 8810 xxxx).
  def create_customers(company)
    CUSTOMERS.each_with_index.map do |full_name, index|
      Customers::FindOrCreate.call(company_id: company.id, full_name:, phone: format("+5058810%04d", index + 1))
    end
  end

  def slots = WEEKDAYS.flat_map { |weekday| OPENING.map { |starts, ends| { weekday:, starts_at_local: starts, ends_at_local: ends } } }

  def book_week(company, branch, services, people, customers, monday, zone)
    counter = 0
    WEEKDAYS.each do |weekday|
      day = monday + (weekday - 1)
      people.product(START_HOURS).each do |professional, hour|
        counter += 1
        # Customers rotate by hour and by person, so nobody is in two chairs at the same time.
        customer = customers[(START_HOURS.index(hour) * people.size + people.index(professional) + weekday) % customers.size]
        starts_at = zone.local(day.year, day.month, day.day, hour)
        appointment = Appointments::Book.call(
          company:, branch:, customer_id: customer.id, services: [ services[counter % services.size] ],
          professional: Appointments::Availability::ProfessionalChoice.of(professional), starts_at:, source: "panel",
          actor: SYSTEM_ACTOR, now: monday.in_time_zone(zone) - 1.day
        )
        advance(appointment, counter)
      end
    end
  end

  # What already happened gets a final status; what is ahead stays open, half of it confirmed.
  def advance(appointment, counter)
    at = appointment.starts_at + 1.minute
    return (move(appointment, :confirm, Time.current) if counter.odd?) if appointment.starts_at >= Time.current

    case counter % 10
    when 0 then Appointments::Cancel.call(appointment:, reason: "customer_request", cancelled_by: "customer", actor: SYSTEM_ACTOR, now: at)
    when 1 then move(appointment, :no_show, at)
    else
      move(appointment, :check_in, at)
      move(appointment, :complete, at)
    end
  end

  def move(appointment, action, now) = Appointments::Transition.call(appointment:, action:, actor: SYSTEM_ACTOR, now:)
end

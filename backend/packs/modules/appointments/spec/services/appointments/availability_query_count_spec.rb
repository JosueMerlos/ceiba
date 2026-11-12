require "rails_helper"

# The number of statements depends on the SHAPE of the request (a concrete professional or :any, with or without a required
# resource kind: the resource queries are skipped when there is no candidate resource) and never on how much data there is:
# professionals, rooms, requested services or days.
RSpec.describe Appointments::Availability do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def first_day = Date.new(2026, 11, 16)

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    Appointments::WeeklySchedule.where(branch_id: branch.id).delete_all
    (1..5).each { create(:weekly_schedule, branch:, weekday: it, starts_at_local: "08:00", ends_at_local: "20:00") }
  end

  def services = (@services ||= [])
  def professionals = (@professionals ||= [])

  def add_service(kind: nil)
    service = create_in(organization, :service, company:, duration_minutes: 30)
    create(:branch_service_override, service:, branch:, duration_minutes: 30)
    create(:service_resource_requirement, service:, kind:) if kind
    professionals.each { create(:professional_service, professional: it, service:) }
    services << service
  end

  # Each professional provides every service, works the whole week and has one appointment and one absence on each of the 14 days.
  def add_professional
    professional = create_in(organization, :professional, company:)
    create(:professional_branch_assignment, professional:, branch:)
    services.each { create(:professional_service, professional:, service: it) }
    (1..5).each { create(:weekly_schedule, branch:, professional:, weekday: it, starts_at_local: "08:00", ends_at_local: "20:00") }
    14.times do |day|
      start = Time.utc(2026, 11, 16, 16) + day.days
      create(:appointment, professional:, branch:, starts_at: start, ends_at: start + 30.minutes)
      create(:time_off, professional:, starts_at: start + 1.hour, ends_at: start + 90.minutes)
    end
    professionals << professional
  end

  def add_room
    room = create(:resource, branch:, kind: "room")
    create(:time_off, resource: room, starts_at: Time.utc(2026, 11, 16, 17), ends_at: Time.utc(2026, 11, 16, 18))
    start = Time.utc(2026, 11, 17, 16)
    create(:appointment, professional: professionals.first, branch:, resource: room, starts_at: start, ends_at: start + 30.minutes)
  end

  def sql_statements
    statements = []
    callback = lambda do |*, payload|
      statements << payload[:sql] unless %w[SCHEMA TRANSACTION CACHE].include?(payload[:name]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def choice(any) = any ? Appointments::Availability::ProfessionalChoice.any : Appointments::Availability::ProfessionalChoice.of(professionals.first)

  def run(requested:, days:, any:)
    described_class.call(company:, branch:, services: services.first(requested), professional: choice(any),
                         from_date: first_day, to_date: first_day + (days - 1), now: Time.utc(2026, 11, 1)).slots
  end

  # Measures the smallest request over the least data, then the largest request over three times the data, and returns both.
  def count_small_and_large(any:, kind:)
    add_service(kind:)
    add_professional
    add_room if kind
    run(requested: 1, days: 1, any:) # warms prepared statements and the schema cache
    small = sql_statements { run(requested: 1, days: 1, any:) }.size

    4.times { add_service(kind:) }
    2.times { add_professional }
    3.times { add_room } if kind
    [ small, sql_statements { run(requested: 5, days: 14, any:) }.size, run(requested: 5, days: 14, any:) ]
  end

  # The exact statements per shape, eligibility included. A new query must be a conscious change of these numbers.
  {
    "profesional concreto sin recurso" => { any: false, kind: nil, count: 9 },
    ":any sin recurso" => { any: true, kind: nil, count: 8 },
    "profesional concreto con sala" => { any: false, kind: "room", count: 12 },
    ":any con sala" => { any: true, kind: "room", count: 11 }
  }.each do |shape, options|
    it "#{shape}: el mismo número de consultas con 1 y con 3 profesionales, 1 y 14 días y 1 y 5 servicios, y con el número exacto de la forma", :aggregate_failures do
      small, large, slots = count_small_and_large(any: options[:any], kind: options[:kind])

      expect(large).to eq(small)
      expect(large).to eq(options[:count])
      expect(slots).not_to be_empty
    end
  end
end

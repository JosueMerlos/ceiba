require "rails_helper"

RSpec.describe Appointments::Availability::DataLoader do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:, duration_minutes: 30) }
  let(:professional) { create_in(organization, :professional, company:) }

  def first_day = Date.new(2026, 11, 16)
  def query_cap = 8

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:professional_branch_assignment, professional:, branch:)
    create(:professional_service, professional:, service:)
    create(:branch_service_override, service:, branch:, duration_minutes: 30)
    (1..5).each do |weekday|
      create(:weekly_schedule, branch:, weekday:)
      create(:weekly_schedule, branch:, professional:, weekday:)
    end
    # One appointment and one absence on each of the 14 days.
    14.times do |day|
      start = Time.utc(2026, 11, 16, 16) + day.days
      create(:appointment, professional:, branch:, starts_at: start, ends_at: start + 30.minutes)
      create(:time_off, professional:, starts_at: start + 1.hour, ends_at: start + 90.minutes)
    end
  end

  def sql_statements
    statements = []
    callback = lambda do |*, payload|
      statements << payload[:sql] unless %w[SCHEMA TRANSACTION CACHE].include?(payload[:name]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def run(days)
    Appointments::Availability.call(company:, branch:, service:, professional:, from_date: first_day, to_date: first_day + (days - 1), now: Time.utc(2026, 11, 1)).slots
  end

  it "emite el mismo número de consultas para 1 día que para 14, y pocas", :aggregate_failures do
    run(1) # warms prepared statements and the schema cache

    one_day = sql_statements { run(1) }
    two_weeks = sql_statements { run(14) }

    expect(two_weeks.size).to eq(one_day.size)
    expect(two_weeks.size).to be <= query_cap
    expect(run(14)).not_to be_empty
  end

  it "devuelve huecos que respetan las citas y ausencias repartidas en las dos semanas", :aggregate_failures do
    slots = run(14)

    busy = Appointments::Appointment.pluck(:blocks_from, :blocks_to) + Appointments::TimeOff.pluck(:starts_at, :ends_at)
    expect(slots).to all(satisfy { |slot| busy.none? { |from, to| slot.starts_at < to && from < slot.ends_at } })
  end
end

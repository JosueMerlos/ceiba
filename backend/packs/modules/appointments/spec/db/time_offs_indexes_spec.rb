require "rails_helper"

RSpec.describe "Índices de ausencias" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def room = @room ||= create(:resource, branch:, kind: "room")

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:service_resource_requirement, service:, kind: "room")
    # Years of past absences: the range asked for must not walk them.
    (1..6).each do |year|
      start = Time.utc(2026 - year, 3, 1, 15)
      create(:time_off, professional:, starts_at: start, ends_at: start + 1.hour)
      create(:time_off, resource: room, starts_at: start, ends_at: start + 1.hour)
    end
  end

  # The statements the loader really emits against time_offs, with literals instead of binds so they can be EXPLAINed.
  def loader_statements
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/FROM "time_offs"/) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveRecord::Base.connection.unprepared_statement do
        Appointments::Availability::DataLoader.call(company:, branch:, services: [ service ], professional:, from_date: Date.new(2026, 11, 16),
                                                    to_date: Date.new(2026, 11, 29))
      end
    end
    statements
  end

  def plan_for(statement)
    connection = ActiveRecord::Base.connection
    connection.execute("SET LOCAL enable_seqscan = off")
    connection.select_values("EXPLAIN #{statement}").join("\n")
  end

  def plan_for_owner(column) = plan_for(loader_statements.find { it.include?("\"#{column}\" IN") || it.include?("\"#{column}\" =") })

  it "la lectura de ausencias de profesionales usa el índice por fin con condición sobre ends_at", :aggregate_failures do
    plan = plan_for_owner("professional_id")

    expect(plan).to include("idx_time_offs_professional_ends")
    expect(plan).to match(/Index Cond:.*ends_at >/)
  end

  it "la lectura de ausencias de recursos usa el índice por fin con condición sobre ends_at", :aggregate_failures do
    plan = plan_for_owner("resource_id")

    expect(plan).to include("idx_time_offs_resource_ends")
    expect(plan).to match(/Index Cond:.*ends_at >/)
  end

  it "los índices por inicio, que no acotan el pasado, ya no existen" do
    names = ActiveRecord::Base.connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = 'time_offs'")

    expect(names).not_to include("idx_time_offs_professional_starts", "idx_time_offs_resource_starts")
  end
end

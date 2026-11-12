require "rails_helper"

# The occupancy reads of the availability loader must be bounded below by blocks_to, so years of past appointments are not walked.
RSpec.describe "Índices de citas" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }
  let(:professional) { create_in(organization, :professional, company:) }
  let(:room) { create(:resource, branch:, kind: "room") }

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:service_resource_requirement, service:, kind: "room")
    (1..6).each do |year|
      start = Time.utc(2026 - year, 3, 1, 15)
      create(:appointment, professional:, branch:, resource: room, starts_at: start)
    end
  end

  # The statements the loader really emits against appointments, with literals instead of binds so they can be EXPLAINed.
  def loader_statements
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/FROM "appointments"/) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveRecord::Base.connection.unprepared_statement do
        Appointments::Availability::DataLoader.call(company:, branch:, services: [ service ], professional: Appointments::Availability::ProfessionalChoice.of(professional),
                                                    from_date: Date.new(2026, 11, 16), to_date: Date.new(2026, 11, 29), requirements: [ [ service.id, "room" ] ])
      end
    end
    statements
  end

  def plan_for(column)
    statement = loader_statements.find { it.include?("\"#{column}\" IN") || it.include?("\"#{column}\" =") }
    connection = ActiveRecord::Base.connection
    connection.execute("SET LOCAL enable_seqscan = off")
    connection.select_values("EXPLAIN #{statement}").join("\n")
  end

  it "la ocupación de recursos usa el índice por fin de bloque con condición sobre blocks_to", :aggregate_failures do
    plan = plan_for("resource_id")

    expect(plan).to include("idx_appointments_resource_blocks")
    expect(plan).to match(/Index Cond:.*blocks_to >/)
  end

  it "la ocupación de profesionales usa el índice por fin de bloque con condición sobre blocks_to", :aggregate_failures do
    plan = plan_for("professional_id")

    expect(plan).to include("idx_appointments_professional_blocks")
    expect(plan).to match(/Index Cond:.*blocks_to >/)
  end
end

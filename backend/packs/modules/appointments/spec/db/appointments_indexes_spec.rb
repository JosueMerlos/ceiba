require "rails_helper"

# The occupancy read of the availability loader for resources must be bounded below by blocks_to, so years of past appointments are not walked.
RSpec.describe "Índices de citas" do
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

  def statement_for(column) = loader_statements.find { it.include?("\"#{column}\" IN") || it.include?("\"#{column}\" =") }

  # Six years of history, every owner with appointments all along, a fifth of them cancelled; the owner asked for is one of twenty.
  def seed_sql(column, owner_id)
    <<~SQL
      INSERT INTO {{clone}} (organization_id, company_id, branch_id, professional_id, resource_id, starts_at, ends_at, blocks_from, blocks_to, status, created_at, updated_at)
      SELECT '#{organization.id}', '#{company.id}', '#{branch.id}',
             #{column == "professional_id" ? "CASE WHEN i % 20 = 0 THEN '#{owner_id}'::uuid ELSE md5(i::text)::uuid END" : "'#{professional.id}'"},
             #{column == "resource_id" ? "CASE WHEN i % 20 = 0 THEN '#{owner_id}'::uuid ELSE md5(i::text)::uuid END" : "NULL"},
             t, t + interval '30 minutes', t, t + interval '30 minutes',
             CASE WHEN i % 5 = 0 THEN 'cancelled' ELSE 'scheduled' END, t, t
      FROM (SELECT i, timestamp '2020-01-01' + i * interval '3 hours' AS t FROM generate_series(1, 20000) AS i) AS series
    SQL
  end

  def plan_for(column, owner_id, index_name)
    IndexPlanProbe.explain_on_clone(table: "appointments", statement: statement_for(column), index_name:, seed_sql: seed_sql(column, owner_id))
  end

  it "la ocupación de recursos emite el dueño y el acotado por blocks_to, y el índice parcial lo cubre", :aggregate_failures do
    statement = statement_for("resource_id")

    expect(statement).to match(/"organization_id" = '#{organization.id}'/)
    expect(statement).to match(/"resource_id" = '#{room.id}'/)
    expect(statement).to include("blocks_to > '")
    expect(IndexPlanProbe.index_shape("appointments", "idx_appointments_resource_blocks"))
      .to eq("btree (organization_id, resource_id, blocks_to) WHERE ((resource_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text) AND ((status)::text <> 'rescheduled'::text))")
  end

  it "la ocupación de recursos usa el índice por fin de bloque con condición sobre blocks_to con historial analizado", :aggregate_failures do
    plan, cloned = plan_for("resource_id", room.id, "idx_appointments_resource_blocks")

    expect(plan).to match(/Index (Only )?Scan using #{cloned}|Bitmap Index Scan on #{cloned}/), plan
    expect(plan).to match(/Index Cond:.*blocks_to >/), plan
  end

  it "la ocupación de profesionales usa el índice por fin de bloque con condición sobre blocks_to con historial analizado", :aggregate_failures do
    plan, cloned = plan_for("professional_id", professional.id, "idx_appointments_professional_blocks")

    expect(plan).to match(/Index (Only )?Scan using #{cloned}|Bitmap Index Scan on #{cloned}/), plan
    expect(plan).to match(/Index Cond:.*blocks_to >/), plan
  end
end

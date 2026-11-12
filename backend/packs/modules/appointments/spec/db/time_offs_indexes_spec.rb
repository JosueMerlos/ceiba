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
        Appointments::Availability::DataLoader.call(company:, branch:, services: [ service ], professional: Appointments::Availability::ProfessionalChoice.of(professional),
                                                    from_date: Date.new(2026, 11, 16), to_date: Date.new(2026, 11, 29), requirements: [ [ service.id, "room" ] ])
      end
    end
    statements
  end

  def statement_for(column) = loader_statements.find { it.include?("\"#{column}\" IN") || it.include?("\"#{column}\" =") }

  # Six years of absences, half of professionals and half of resources; the owner asked for is one of twenty.
  def seed_sql(column, owner_id)
    owner = "CASE WHEN i % 20 = 0 THEN '#{owner_id}'::uuid ELSE md5(i::text)::uuid END"
    <<~SQL
      INSERT INTO {{clone}} (organization_id, company_id, owner_type, professional_id, resource_id, starts_at, ends_at, created_at, updated_at)
      SELECT '#{organization.id}', '#{company.id}', '#{column == "professional_id" ? "professional" : "resource"}',
             #{column == "professional_id" ? owner : "NULL"}, #{column == "resource_id" ? owner : "NULL"},
             t, t + interval '1 hour', t, t
      FROM (SELECT i, timestamp '2020-01-01' + i * interval '3 hours' AS t FROM generate_series(1, 20000) AS i) AS series
    SQL
  end

  def plan_for(column, owner_id, index_name)
    IndexPlanProbe.explain_on_clone(table: "time_offs", statement: statement_for(column), index_name:, seed_sql: seed_sql(column, owner_id))
  end

  it "la lectura de ausencias emite el dueño y el acotado por ends_at, y los índices parciales los cubren", :aggregate_failures do
    expect(statement_for("professional_id")).to match(/"professional_id" = '#{professional.id}'.*ends_at > '/)
    expect(statement_for("resource_id")).to match(/"resource_id" = '#{room.id}'.*ends_at > '/)
    expect(IndexPlanProbe.index_shape("time_offs", "idx_time_offs_professional_ends")).to eq("btree (organization_id, professional_id, ends_at) WHERE (professional_id IS NOT NULL)")
    expect(IndexPlanProbe.index_shape("time_offs", "idx_time_offs_resource_ends")).to eq("btree (organization_id, resource_id, ends_at) WHERE (resource_id IS NOT NULL)")
  end

  it "la lectura de ausencias de profesionales usa el índice por fin con condición sobre ends_at con historial analizado", :aggregate_failures do
    plan, cloned = plan_for("professional_id", professional.id, "idx_time_offs_professional_ends")

    expect(plan).to match(/Index (Only )?Scan using #{cloned}|Bitmap Index Scan on #{cloned}/), plan
    expect(plan).to match(/Index Cond:.*ends_at >/), plan
  end

  it "la lectura de ausencias de recursos usa el índice por fin con condición sobre ends_at con historial analizado", :aggregate_failures do
    plan, cloned = plan_for("resource_id", room.id, "idx_time_offs_resource_ends")

    expect(plan).to match(/Index (Only )?Scan using #{cloned}|Bitmap Index Scan on #{cloned}/), plan
    expect(plan).to match(/Index Cond:.*ends_at >/), plan
  end

  it "los índices por inicio, que no acotan el pasado, ya no existen" do
    names = ActiveRecord::Base.connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = 'time_offs'")

    expect(names).not_to include("idx_time_offs_professional_starts", "idx_time_offs_resource_starts")
  end
end

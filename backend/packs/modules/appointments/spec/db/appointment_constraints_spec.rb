require "rails_helper"

# The database is the final arbiter of the agenda: these specs insert with plain SQL so no model validation can hide a missing constraint.
RSpec.describe "Restricciones de citas en la base de datos" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }
  let(:customer) { create_in(organization, :customer, company:) }
  let(:ten) { Time.utc(2026, 11, 16, 10) }

  around { |example| with_tenant(organization) { example.run } }

  def quote(value) = ApplicationRecord.connection.quote(value)

  # Inserts one appointment row. `blocks_from`/`blocks_to` default to the slot itself.
  def insert_appointment(from: ten, to: from + 1.hour, professional: self.professional, resource: nil, status: "scheduled", branch: self.branch,
                         customer: self.customer, source: "panel", starts_at: from, ends_at: to, blocks_from: from, blocks_to: to)
    ApplicationRecord.connection.select_value(<<~SQL.squish)
      INSERT INTO appointments (organization_id, company_id, branch_id, professional_id, resource_id, customer_id, source, created_by_type,
                                starts_at, ends_at, blocks_from, blocks_to, status, created_at, updated_at)
      VALUES (#{quote(organization.id)}, #{quote(company.id)}, #{quote(branch.id)}, #{quote(professional.id)}, #{quote(resource&.id)},
              #{quote(customer.id)}, #{quote(source)}, 'system', #{quote(starts_at)}, #{quote(ends_at)}, #{quote(blocks_from)}, #{quote(blocks_to)},
              #{quote(status)}, now(), now())
      RETURNING id
    SQL
  end

  def rejected_by(error, name, &)
    expect { savepoint(&) }.to raise_error(error, /#{name}/)
  end

  describe "no_overlap_professional" do
    it "rechaza dos citas bloqueantes del mismo profesional con bloques solapados" do
      insert_appointment(from: ten)

      rejected_by(ActiveRecord::ExclusionViolation, "no_overlap_professional") { insert_appointment(from: ten + 30.minutes) }
    end

    it "permite bloques contiguos del mismo profesional porque el rango es semiabierto" do
      insert_appointment(from: ten, to: ten + 1.hour)

      expect(insert_appointment(from: ten + 1.hour, to: ten + 2.hours)).to be_present
    end

    it "permite una cita en un hueco liberado por una cancelada o reprogramada", :aggregate_failures do
      %w[cancelled rescheduled].each_with_index do |status, index|
        from = ten + index.days
        insert_appointment(from:, status:)

        expect(insert_appointment(from:)).to be_present
      end
    end

    it "rechaza una cita sobre un no_show, que sigue bloqueando" do
      insert_appointment(from: ten, status: "no_show")

      rejected_by(ActiveRecord::ExclusionViolation, "no_overlap_professional") { insert_appointment(from: ten) }
    end

    it "permite la misma hora a otro profesional" do
      insert_appointment(from: ten)

      expect(insert_appointment(from: ten, professional: create(:professional, company:))).to be_present
    end
  end

  describe "no_overlap_resource" do
    let(:chair) { create(:resource, branch:) }

    it "rechaza el mismo recurso con otro profesional y bloques solapados" do
      insert_appointment(from: ten, resource: chair)

      rejected_by(ActiveRecord::ExclusionViolation, "no_overlap_resource") do
        insert_appointment(from: ten + 15.minutes, resource: chair, professional: create(:professional, company:))
      end
    end

    it "permite solapar cuando las dos citas no usan recurso" do
      insert_appointment(from: ten)

      expect(insert_appointment(from: ten, professional: create(:professional, company:))).to be_present
    end
  end

  describe "claves foráneas compuestas" do
    it "rechaza un recurso de otra sucursal de la misma empresa" do
      other_branch_resource = create(:resource, branch: create(:branch, company:))

      rejected_by(ActiveRecord::InvalidForeignKey, "fk_appointments_resource") { insert_appointment(resource: other_branch_resource) }
    end

    it "rechaza un cliente de otra empresa de la misma organización" do
      foreign_customer = create(:customer, company: create(:company))

      rejected_by(ActiveRecord::InvalidForeignKey, "fk_appointments_customer") { insert_appointment(customer: foreign_customer) }
    end
  end

  describe "chk_appointments_valid_interval" do
    it "rechaza una cita sin duración, con bloque que empieza después o que termina antes", :aggregate_failures do
      invalid = [
        { to: ten },
        { blocks_from: ten + 1.minute },
        { blocks_to: ten + 59.minutes }
      ]

      invalid.each { |attributes| rejected_by(ActiveRecord::CheckViolation, "chk_appointments_valid_interval") { insert_appointment(from: ten, **attributes) } }
    end
  end

  describe "chk_appointments_source" do
    it "rechaza un origen desconocido" do
      rejected_by(ActiveRecord::CheckViolation, "chk_appointments_source") { insert_appointment(source: "otro") }
    end
  end

  describe "appointment_services" do
    let(:service) { create_in(organization, :service, company:) }
    let(:appointment_id) { insert_appointment }

    def insert_line(position: 0, price_minor: 20_000, currency: "NIO")
      ApplicationRecord.connection.execute(<<~SQL.squish)
        INSERT INTO appointment_services (organization_id, company_id, appointment_id, service_id, position, duration_minutes,
                                          buffer_before_minutes, buffer_after_minutes, price_minor, currency, created_at)
        VALUES (#{quote(organization.id)}, #{quote(company.id)}, #{quote(appointment_id)}, #{quote(service.id)}, #{position}, 30, 0, 0,
                #{price_minor}, #{quote(currency)}, now())
      SQL
    end

    it "rechaza una moneda en minúsculas" do
      rejected_by(ActiveRecord::CheckViolation, "chk_appointment_services_currency") { insert_line(currency: "usd") }
    end

    it "rechaza un precio negativo" do
      rejected_by(ActiveRecord::CheckViolation, "chk_appointment_services_price") { insert_line(price_minor: -1) }
    end

    it "rechaza una posición repetida dentro de la misma cita" do
      insert_line(position: 0)

      expect { savepoint { insert_line(position: 0) } }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

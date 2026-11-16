require "rails_helper"

# The database is the final arbiter of the agenda: these specs insert with plain SQL so no model validation can hide a missing constraint.
RSpec.describe "Restricciones de citas en la base de datos" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  around { |example| with_tenant(organization) { example.run } }

  # Eager: a record first built inside a rolled-back savepoint would not exist for the next attempt of the same example.
  before { [ branch, professional, customer ] }

  def customer = @customer ||= create_in(organization, :customer, company:)
  def ten = Time.utc(2026, 11, 16, 10)

  def quote(value) = ApplicationRecord.connection.quote(value)

  # Inserts one appointment row. `blocks_from`/`blocks_to` default to the slot itself.
  def insert_appointment(from: ten, to: from + 1.hour, professional: self.professional, resource: nil, status: "scheduled", branch: self.branch,
                         customer: self.customer, source: "panel", created_by_type: "system", created_by_id: nil, starts_at: from, ends_at: to, blocks_from: from, blocks_to: to)
    ApplicationRecord.connection.select_value(<<~SQL.squish)
      INSERT INTO appointments (organization_id, company_id, branch_id, professional_id, resource_id, customer_id, source, created_by_type,
                                created_by_id, starts_at, ends_at, blocks_from, blocks_to, status, created_at, updated_at)
      VALUES (#{quote(organization.id)}, #{quote(company.id)}, #{quote(branch.id)}, #{quote(professional.id)}, #{quote(resource&.id)},
              #{quote(customer.id)}, #{quote(source)}, #{quote(created_by_type)}, #{quote(created_by_id)}, #{quote(starts_at)}, #{quote(ends_at)}, #{quote(blocks_from)}, #{quote(blocks_to)},
              #{quote(status)}, now(), now())
      RETURNING id
    SQL
  end

  def violating(error, name) = raise_error(error, /#{name}/)

  describe "no_overlap_professional" do
    it "rechaza dos citas bloqueantes del mismo profesional con bloques solapados" do
      insert_appointment(from: ten)

      expect { savepoint { insert_appointment(from: ten + 30.minutes) } }.to violating(ActiveRecord::ExclusionViolation, "no_overlap_professional")
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

      expect { savepoint { insert_appointment(from: ten) } }.to violating(ActiveRecord::ExclusionViolation, "no_overlap_professional")
    end

    it "permite la misma hora a otro profesional" do
      insert_appointment(from: ten)

      expect(insert_appointment(from: ten, professional: create(:professional, company:))).to be_present
    end
  end

  describe "no_overlap_resource" do
    def chair = @chair ||= create(:resource, branch:)

    it "rechaza el mismo recurso con otro profesional y bloques solapados" do
      insert_appointment(from: ten, resource: chair)

      expect { savepoint { insert_appointment(from: ten + 15.minutes, resource: chair, professional: create(:professional, company:)) } }
        .to violating(ActiveRecord::ExclusionViolation, "no_overlap_resource")
    end

    it "permite solapar cuando las dos citas no usan recurso" do
      insert_appointment(from: ten)

      expect(insert_appointment(from: ten, professional: create(:professional, company:))).to be_present
    end
  end

  describe "claves foráneas compuestas" do
    it "rechaza un recurso de otra sucursal de la misma empresa" do
      other_branch_resource = create(:resource, branch: create(:branch, company:))

      expect { savepoint { insert_appointment(resource: other_branch_resource) } }.to violating(ActiveRecord::InvalidForeignKey, "fk_appointments_resource")
    end

    it "rechaza un cliente de otra empresa de la misma organización" do
      foreign_customer = create(:customer, company: create(:company))

      expect { savepoint { insert_appointment(customer: foreign_customer) } }.to violating(ActiveRecord::InvalidForeignKey, "fk_appointments_customer")
    end
  end

  describe "chk_appointments_valid_interval" do
    it "rechaza una cita sin duración, con bloque que empieza después o que termina antes", :aggregate_failures do
      invalid = [
        { to: ten },
        { blocks_from: ten + 1.minute },
        { blocks_to: ten + 59.minutes }
      ]

      invalid.each do |attributes|
        expect { savepoint { insert_appointment(from: ten, **attributes) } }.to violating(ActiveRecord::CheckViolation, "chk_appointments_valid_interval")
      end
    end
  end

  describe "chk_appointments_source" do
    it "rechaza un origen desconocido" do
      expect { savepoint { insert_appointment(source: "otro") } }.to violating(ActiveRecord::CheckViolation, "chk_appointments_source")
    end
  end

  describe "chk_appointments_created_by_type" do
    it "acepta cada tipo de actor que la auditoría conoce, platform_staff incluido", :aggregate_failures do
      %w[user api_key system public_token platform_staff].each_with_index do |type, index|
        expect(insert_appointment(from: ten + index.days, created_by_type: type)).to be_present
      end
    end

    it "rechaza un tipo de actor desconocido" do
      expect { savepoint { insert_appointment(created_by_type: "robot") } }.to violating(ActiveRecord::CheckViolation, "chk_appointments_created_by_type")
    end
  end

  describe "chk_appointments_created_by_user_id" do
    it "rechaza una cita creada por un usuario sin su id" do
      expect { savepoint { insert_appointment(created_by_type: "user", created_by_id: nil) } }
        .to violating(ActiveRecord::CheckViolation, "chk_appointments_created_by_user_id")
    end

    it "acepta al usuario con su id y a los demás actores sin id", :aggregate_failures do
      expect(insert_appointment(from: ten, created_by_type: "user", created_by_id: SecureRandom.uuid)).to be_present
      expect(insert_appointment(from: ten + 1.day, created_by_type: "system", created_by_id: nil)).to be_present
    end
  end

  describe "appointment_services" do
    def service = @service ||= create_in(organization, :service, company:)
    def appointment_id = @appointment_id ||= insert_appointment

    def insert_line(position: 0, price_minor: 20_000, currency: "NIO")
      ApplicationRecord.connection.execute(<<~SQL.squish)
        INSERT INTO appointment_services (organization_id, company_id, appointment_id, service_id, position, duration_minutes,
                                          buffer_before_minutes, buffer_after_minutes, price_minor, currency, created_at)
        VALUES (#{quote(organization.id)}, #{quote(company.id)}, #{quote(appointment_id)}, #{quote(service.id)}, #{position}, 30, 0, 0,
                #{price_minor}, #{quote(currency)}, now())
      SQL
    end

    it "rechaza una moneda en minúsculas" do
      expect { savepoint { insert_line(currency: "usd") } }.to violating(ActiveRecord::CheckViolation, "chk_appointment_services_currency")
    end

    it "rechaza un precio negativo" do
      expect { savepoint { insert_line(price_minor: -1) } }.to violating(ActiveRecord::CheckViolation, "chk_appointment_services_price")
    end

    it "rechaza cualquier UPDATE de una línea, también por SQL", :aggregate_failures do
      insert_line

      expect { savepoint { ApplicationRecord.connection.execute("UPDATE appointment_services SET price_minor = 1") } }
        .to raise_error(ActiveRecord::StatementInvalid, /appointment_services.*UPDATE/)
      expect(ApplicationRecord.connection.select_values("SELECT price_minor FROM appointment_services")).to eq([ 20_000 ])
    end

    it "deja borrar las líneas en cascada al borrar la cita", :aggregate_failures do
      insert_line

      ApplicationRecord.connection.execute("DELETE FROM appointments WHERE id = #{quote(appointment_id)}")

      expect(ApplicationRecord.connection.select_value("SELECT count(*) FROM appointment_services")).to eq(0)
    end

    it "rechaza una posición repetida dentro de la misma cita" do
      insert_line(position: 0)

      expect { savepoint { insert_line(position: 0) } }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

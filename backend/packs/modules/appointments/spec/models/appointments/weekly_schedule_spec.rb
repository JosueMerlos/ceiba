require "rails_helper"

RSpec.describe Appointments::WeeklySchedule do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:other_branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def errors_of(schedule, attribute) = schedule.errors.where(attribute).map(&:type)
  def assign(professional, *branches) = branches.each { create(:professional_branch_assignment, professional:, branch: it) }

  def slot(starts, ends, weekday: 1, **owner)
    build(:weekly_schedule, **{ branch: }.merge(owner), weekday:, starts_at_local: starts, ends_at_local: ends)
  end

  def exclusion_violation = raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::ExclusionViolation) }

  context "con dos franjas del mismo profesional el lunes, 9-13 y 12-15, en la misma sucursal" do
    it "el modelo da overlap y la base de datos lanza la exclusión aunque se salte la validación", :aggregate_failures do
      with_tenant(organization) do
        assign(professional, branch)
        slot("09:00", "13:00", professional:).save!
        overlapping = slot("12:00", "15:00", professional:)

        expect(overlapping).not_to be_valid
        expect(errors_of(overlapping, :base)).to eq([ :overlap ])
        expect { savepoint { overlapping.save!(validate: false) } }.to exclusion_violation
      end
    end
  end

  context "con el mismo profesional el lunes 9-13 en una sucursal y 12-15 en otra" do
    it "se rechaza: la persona no está en dos sucursales a la vez", :aggregate_failures do
      with_tenant(organization) do
        assign(professional, branch, other_branch)
        slot("09:00", "13:00", professional:).save!
        elsewhere = slot("12:00", "15:00", professional:, branch: other_branch)

        expect(elsewhere).not_to be_valid
        expect(errors_of(elsewhere, :base)).to eq([ :overlap ])
        expect { savepoint { elsewhere.save!(validate: false) } }.to exclusion_violation
      end
    end
  end

  context "con franjas que se tocan en el borde (9-13 y 13-15)" do
    it "son válidas: el rango es semiabierto" do
      with_tenant(organization) do
        assign(professional, branch)
        slot("09:00", "13:00", professional:).save!

        expect(slot("13:00", "15:00", professional:)).to be_valid
        expect { savepoint { slot("13:00", "15:00", professional:).save!(validate: false) } }.not_to raise_error
      end
    end
  end

  context "con el mismo horario para dueños distintos" do
    it "dos profesionales a la misma hora son válidos, como el mismo horario en otro día", :aggregate_failures do
      with_tenant(organization) do
        other = create(:professional, company:)
        assign(professional, branch)
        assign(other, branch)
        slot("09:00", "13:00", professional:).save!

        expect(slot("09:00", "13:00", professional: other)).to be_valid
        expect(slot("09:00", "13:00", professional:, weekday: 2)).to be_valid
      end
    end

    it "la sucursal y su profesional pueden tener la misma franja (son dueños distintos)" do
      with_tenant(organization) do
        assign(professional, branch)
        slot("09:00", "13:00").save!

        expect(slot("09:00", "13:00", professional:)).to be_valid
      end
    end
  end

  context "con franjas de la sucursal" do
    it "se solapan entre sí, pero no con las de otra sucursal", :aggregate_failures do
      with_tenant(organization) do
        slot("09:00", "13:00").save!
        overlapping = slot("12:00", "15:00")

        expect(overlapping).not_to be_valid
        expect { savepoint { overlapping.save!(validate: false) } }.to exclusion_violation
        expect(slot("12:00", "15:00", branch: other_branch)).to be_valid
      end
    end
  end

  context "con franjas de un recurso" do
    it "se solapan entre sí; otro recurso de la misma sucursal no", :aggregate_failures do
      with_tenant(organization) do
        chair = create(:resource, branch:)
        slot("09:00", "13:00", resource: chair).save!
        overlapping = slot("12:00", "15:00", resource: chair)

        expect(overlapping).not_to be_valid
        expect { savepoint { overlapping.save!(validate: false) } }.to exclusion_violation
        expect(slot("12:00", "15:00", resource: create(:resource, branch:))).to be_valid
      end
    end

    it "un recurso de otra sucursal no admite horario en esta: la FK compuesta lo impide", :aggregate_failures do
      with_tenant(organization) do
        foreign = create(:resource, branch: other_branch)
        schedule = slot("09:00", "13:00", resource: foreign)

        expect(schedule).not_to be_valid
        expect(errors_of(schedule, :resource_id)).to eq([ :invalid ])
        expect { savepoint { schedule.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_ws_resource/)
      end
    end
  end

  describe "restricciones de la base de datos y del modelo" do
    def expect_violation(schedule, constraint)
      expect(schedule).not_to be_valid
      expect { savepoint { schedule.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /#{constraint}/)
    end

    it "una franja que no termina después de empezar es inválida (CHECK)" do
      with_tenant(organization) { expect_violation(slot("13:00", "13:00"), "chk_ws_range") }
    end

    it "un día fuera de 0-6 es inválido (CHECK)", :aggregate_failures do
      with_tenant(organization) do
        expect_violation(slot("09:00", "13:00", weekday: 7), "chk_ws_weekday")
        expect(slot("09:00", "13:00", weekday: 0)).to be_valid
        expect(slot("09:00", "13:00", weekday: 6)).to be_valid
      end
    end

    it "un horario de profesional con resource_id es incoherente (CHECK de dueño)" do
      with_tenant(organization) do
        assign(professional, branch)
        schedule = slot("09:00", "13:00", professional:)
        schedule.resource_id = create(:resource, branch:).id

        expect_violation(schedule, "chk_ws_owner")
      end
    end

    it "un horario de sucursal con profesional es incoherente (CHECK de dueño)" do
      with_tenant(organization) do
        assign(professional, branch)
        schedule = slot("09:00", "13:00")
        schedule.professional_id = professional.id

        expect_violation(schedule, "chk_ws_owner")
      end
    end

    it "un tipo de dueño desconocido es inválido (CHECK)" do
      with_tenant(organization) { expect_violation(slot("09:00", "13:00").tap { it.owner_type = "robot" }, "chk_ws_owner") }
    end

    it "los segundos no existen: 10:00:30 es inválido en el modelo y en la base (CHECK de precisión de minuto)", :aggregate_failures do
      with_tenant(organization) do
        schedule = slot("10:00:00", "10:00:30")

        expect_violation(schedule, "chk_ws_minute_precision")
        expect(errors_of(schedule, :ends_at_local)).to eq([ :invalid ])
      end
    end

    it "un profesional NO asignado a la sucursal no tiene horario ahí: la FK compuesta lo impide", :aggregate_failures do
      with_tenant(organization) do
        schedule = slot("09:00", "13:00", professional:)

        expect(schedule).not_to be_valid
        expect(errors_of(schedule, :professional_id)).to eq([ :invalid ])
        expect { savepoint { schedule.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_ws_assignment/)
      end
    end

    it "una sucursal de otra empresa es inválida y la FK compuesta lo impide", :aggregate_failures do
      with_tenant(organization) do
        foreign = create(:branch, company: create(:company))
        schedule = slot("09:00", "13:00", branch: foreign).tap { it.company_id = company.id }

        expect(schedule).not_to be_valid
        expect { savepoint { schedule.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_ws_branch/)
      end
    end
  end

  describe "hora local" do
    it "guarda la hora del reloj de la pared sin convertirla por la zona de la aplicación", :aggregate_failures do
      with_tenant(organization) do
        Time.use_zone("Pacific/Auckland") do
          schedule = slot("09:00", "13:30").tap(&:save!)

          stored = ApplicationRecord.connection.select_one("SELECT starts_at_local::text AS starts, ends_at_local::text AS ends FROM weekly_schedules WHERE id = '#{schedule.id}'")
          expect(stored).to eq("starts" => "09:00:00", "ends" => "13:30:00")
          expect(schedule.reload).to have_attributes(starts_at_local: Time.utc(2000, 1, 1, 9, 0), ends_at_local: Time.utc(2000, 1, 1, 13, 30))
        end
      end
    end
  end
end

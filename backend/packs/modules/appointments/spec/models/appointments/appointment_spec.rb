require "rails_helper"

RSpec.describe Appointments::Appointment do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def build_for(**attributes) = build(:appointment, professional:, branch:, **attributes)

  describe ".blocking" do
    it "excluye las citas canceladas y reprogramadas y conserva el resto", :aggregate_failures do
      with_tenant(organization) do
        statuses = %w[scheduled confirmed completed no_show cancelled rescheduled]
        rows = statuses.to_h { |status| [ status, create(:appointment, professional:, branch:, status:) ] }

        expect(described_class.blocking).to contain_exactly(*rows.values_at("scheduled", "confirmed", "completed", "no_show"))
      end
    end
  end

  describe ".overlapping" do
    let(:base) { Time.utc(2026, 11, 16, 10) }
    let(:appointment) { create_in(organization, :appointment, professional:, branch:, starts_at: base, ends_at: base + 30.minutes) }

    it "usa el bloqueo (blocks_*) y no el horario de la cita", :aggregate_failures do
      with_tenant(organization) do
        padded = create(:appointment, professional:, branch:, starts_at: base, ends_at: base + 30.minutes,
                                      blocks_from: base - 10.minutes, blocks_to: base + 40.minutes)

        expect(described_class.overlapping(base - 5.minutes, base - 1.minute)).to contain_exactly(padded)
        expect(described_class.overlapping(base + 35.minutes, base + 50.minutes)).to contain_exactly(padded)
      end
    end

    it "es semiabierto: una cita que termina donde empieza el rango, o empieza donde termina, no solapa", :aggregate_failures do
      with_tenant(organization) do
        appointment

        expect(described_class.overlapping(base + 30.minutes, base + 60.minutes)).to be_empty
        expect(described_class.overlapping(base - 30.minutes, base)).to be_empty
        expect(described_class.overlapping(base + 29.minutes, base + 60.minutes)).to contain_exactly(appointment)
        expect(described_class.overlapping(base - 30.minutes, base + 1.minute)).to contain_exactly(appointment)
      end
    end

    it "encuentra la cita que contiene el rango entero y la que lo contiene por dentro", :aggregate_failures do
      with_tenant(organization) do
        appointment

        expect(described_class.overlapping(base + 10.minutes, base + 20.minutes)).to contain_exactly(appointment)
        expect(described_class.overlapping(base - 1.hour, base + 2.hours)).to contain_exactly(appointment)
      end
    end
  end

  describe "claves foráneas compuestas (adversarial, tenancy)" do
    let(:other_company) { create_in(organization, :company) }

    it "persiste una cita de la misma empresa" do
      with_tenant(organization) { expect(build_for.save!).to be(true) }
    end

    it "rechaza una sucursal de OTRA empresa de la misma organización", :aggregate_failures do
      with_tenant(organization) do
        foreign_branch = create(:branch, company: other_company)

        expect { savepoint { build_for(branch: foreign_branch).save!(validate: false) } }
          .to raise_error(ActiveRecord::InvalidForeignKey, /fk_appointments_branch/)
      end
    end

    it "rechaza un profesional de OTRA empresa de la misma organización", :aggregate_failures do
      with_tenant(organization) do
        foreign_professional = create(:professional, company: other_company)

        expect { savepoint { build_for.tap { it.professional_id = foreign_professional.id }.save!(validate: false) } }
          .to raise_error(ActiveRecord::InvalidForeignKey, /fk_appointments_professional/)
      end
    end
  end
end

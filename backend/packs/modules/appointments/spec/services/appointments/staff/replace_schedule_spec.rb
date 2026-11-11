require "rails_helper"

RSpec.describe Appointments::Staff::ReplaceSchedule do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:other_branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def events(action) = Audit::Event.where(action:).to_a
  def hours(**owner) = Appointments::WeeklySchedule.where(**owner).order(:weekday, :starts_at_local).map { [ it.branch_id, it.weekday, it.starts_at_local.strftime("%H:%M"), it.ends_at_local.strftime("%H:%M") ] }
  def slot(weekday, starts, ends) = { weekday:, starts_at_local: starts, ends_at_local: ends }

  before { with_tenant(organization) { create(:professional_branch_assignment, professional:, branch:) } }

  it "reemplaza TODAS las franjas del profesional en la sucursal y audita una vez con el antes y el después", :aggregate_failures do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "08:00", ends_at_local: "12:00")
      create(:weekly_schedule, branch:, professional:, weekday: 2, starts_at_local: "08:00", ends_at_local: "12:00")

      result = described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00"), slot(1, "14:00", "18:00"), slot(3, "09:00", "13:00") ])

      expect(hours(professional_id: professional.id)).to eq([ [ branch.id, 1, "09:00", "13:00" ], [ branch.id, 1, "14:00", "18:00" ], [ branch.id, 3, "09:00", "13:00" ] ])
      expect(result.map(&:weekday)).to eq([ 1, 1, 3 ])
      event = events("schedule.replaced").sole
      expect(event.auditable_id).to eq(professional.id)
      expect(event.before["slots"]).to eq([ { "weekday" => 1, "starts_at_local" => "08:00", "ends_at_local" => "12:00" }, { "weekday" => 2, "starts_at_local" => "08:00", "ends_at_local" => "12:00" } ])
      expect(event.after["slots"].size).to eq(3)
      expect(event.metadata).to include("branch_id" => branch.id)
    end
  end

  it "una lista vacía quita todo el horario del dueño en esa sucursal" do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:)

      described_class.call(owner: professional, branch_id: branch.id, slots: [])

      expect(hours(professional_id: professional.id)).to be_empty
    end
  end

  it "no toca las franjas del mismo profesional en otra sucursal, ni las de otro profesional, ni las de la sucursal", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch: other_branch)
      other_professional = create(:professional, company:)
      create(:professional_branch_assignment, professional: other_professional, branch:)
      create(:weekly_schedule, branch: other_branch, professional:, weekday: 4)
      create(:weekly_schedule, branch:, professional: other_professional)
      create(:weekly_schedule, branch:)

      described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00") ])

      expect(hours(professional_id: professional.id)).to contain_exactly([ other_branch.id, 4, "09:00", "13:00" ], [ branch.id, 1, "09:00", "13:00" ])
      expect(hours(professional_id: other_professional.id).size).to eq(1)
      expect(hours(owner_type: "branch").size).to eq(1)
    end
  end

  it "un solape entre las franjas nuevas lanza RecordInvalid con slots: overlap y deja intactas las previas", :aggregate_failures do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:, weekday: 2, starts_at_local: "08:00", ends_at_local: "12:00")

      expect { described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00"), slot(1, "12:00", "15:00") ]) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:slots).map(&:type)).to eq([ :overlap ]) }

      expect(hours(professional_id: professional.id)).to eq([ [ branch.id, 2, "08:00", "12:00" ] ])
      expect(events("schedule.replaced")).to be_empty
    end
  end

  it "un solape con el horario del mismo profesional en OTRA sucursal también es slots: overlap", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch: other_branch)
      create(:weekly_schedule, branch: other_branch, professional:, weekday: 1, starts_at_local: "12:00", ends_at_local: "15:00")

      expect { described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00") ]) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:slots).map(&:type)).to eq([ :overlap ]) }

      expect(hours(professional_id: professional.id)).to eq([ [ other_branch.id, 1, "12:00", "15:00" ] ])
    end
  end

  it "la exclusión de la base de datos (carrera entre sesiones) se traduce a slots: overlap dentro del savepoint", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch: other_branch)
      create(:weekly_schedule, branch:, professional:, weekday: 5, starts_at_local: "10:00", ends_at_local: "12:00")
      # A writer that committed after the model's own check would reach the constraint: simulate it by skipping that check.
      allow(Appointments::WeeklySchedule).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap { |record| record.define_singleton_method(:no_overlap) { nil } }
      end

      expect { described_class.call(owner: professional, branch_id: other_branch.id, slots: [ slot(5, "11:00", "13:00") ]) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:slots).map(&:type)).to eq([ :overlap ]) }

      expect(hours(professional_id: professional.id)).to eq([ [ branch.id, 5, "10:00", "12:00" ] ])
    end
  end

  it "una franja con segundos (10:00:30) lanza RecordInvalid con slots: invalid y no cambia nada (precisión de minuto)", :aggregate_failures do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:)

      expect { described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "10:00:00", "10:00:30") ]) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:slots).map(&:type)).to eq([ :invalid ]) }

      expect(hours(professional_id: professional.id).size).to eq(1)
    end
  end

  it "un día fuera de 0-6 o una hora ilegible es slots: invalid" do
    with_tenant(organization) do
      [ slot(7, "09:00", "13:00"), slot(1, "nueve", "13:00"), slot(1, "13:00", "09:00") ].each do |bad|
        expect { described_class.call(owner: professional, branch_id: branch.id, slots: [ bad ]) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:slots).map(&:type)).to eq([ :invalid ]) }
      end
    end
  end

  it "reemplaza el horario de la sucursal y el de un recurso", :aggregate_failures do
    with_tenant(organization) do
      chair = create(:resource, branch:)
      create(:weekly_schedule, branch:, weekday: 1)

      described_class.call(owner: Tenancy::Directory.branch!(branch.id, company_id: company.id), branch_id: branch.id, slots: [ slot(2, "08:00", "18:00") ])
      described_class.call(owner: chair, branch_id: branch.id, slots: [ slot(3, "09:00", "12:00") ])

      expect(hours(owner_type: "branch")).to eq([ [ branch.id, 2, "08:00", "18:00" ] ])
      expect(hours(resource_id: chair.id)).to eq([ [ branch.id, 3, "09:00", "12:00" ] ])
      expect(events("schedule.replaced").size).to eq(2)
    end
  end

  it "no audita si las franjas no cambian" do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")

      described_class.call(owner: professional, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00") ])

      expect(events("schedule.replaced")).to be_empty
    end
  end

  it "toma el candado consultivo del dueño: dos reemplazos del mismo profesional se serializan" do
    with_tenant(organization) do
      statements = []
      subscriber = ->(*, payload) { statements << payload[:sql] if payload[:sql].include?("pg_advisory_xact_lock") }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { described_class.call(owner: professional, branch_id: branch.id, slots: []) }

      expect(statements.size).to eq(1)
      expect(statements.sole).to include("ceiba.appointments.schedule:#{professional.id}")
    end
  end

  it "un profesional o un recurso archivado es historia de solo lectura (base: archived) y conserva su horario", :aggregate_failures do
    with_tenant(organization) do
      create(:weekly_schedule, branch:, professional:, weekday: 2)
      professional.update!(archived_at: Time.current)
      archived_chair = create(:resource, branch:, archived_at: Time.current)

      [ professional, archived_chair ].each do |owner|
        expect { described_class.call(owner:, branch_id: branch.id, slots: [ slot(1, "09:00", "13:00") ]) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:base).map(&:type)).to eq([ :archived ]) }
      end
      expect(hours(professional_id: professional.id).size).to eq(1)
    end
  end
end

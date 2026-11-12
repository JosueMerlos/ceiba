require "rails_helper"

RSpec.describe Appointments::Availability do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:, duration_minutes: 45) }
  let(:professional) { create_in(organization, :professional, company:) }

  # Monday. The branch is in America/Managua (UTC-6, no DST), so 10:00 local is 16:00Z.
  def monday = Date.new(2026, 11, 16)
  def long_before = Time.utc(2026, 11, 1)

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:professional_branch_assignment, professional:, branch:)
    create(:professional_service, professional:, service:)
    create(:branch_service_override, service:, branch:, duration_minutes: 30)
  end

  def open_hours(starts: "09:00", ends: "13:00", weekday: 1)
    create(:weekly_schedule, branch:, weekday:, starts_at_local: starts, ends_at_local: ends)
    create(:weekly_schedule, branch:, professional:, weekday:, starts_at_local: starts, ends_at_local: ends)
  end

  def availability(**overrides)
    described_class.call(company:, branch:, service:, professional:, from_date: monday, to_date: monday, now: long_before, **overrides)
  end

  def local_starts(slots) = slots.map { it.starts_at.in_time_zone(branch.time_zone).strftime("%H:%M") }

  def book(at_utc_hour, minutes: 30, **attributes)
    start = Time.utc(2026, 11, 16, at_utc_hour)
    create(:appointment, professional:, branch:, starts_at: start, ends_at: start + minutes.minutes, **attributes)
  end

  def second_branch
    create(:branch, company:).tap { create(:professional_branch_assignment, professional:, branch: it) }
  end

  describe "caso base de extremo a extremo" do
    it "horario 9-13, cita 10:00-10:30 y duración de la sucursal de 30: ningún hueco solapa la cita", :aggregate_failures do
      open_hours
      book(16)

      slots = availability

      expect(local_starts(slots)).to eq(%w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
      expect(slots.map { it.ends_at - it.starts_at }.uniq).to eq([ 30.minutes.to_i ])
      expect(slots.first.starts_at).to eq(Time.utc(2026, 11, 16, 15))
    end

    it "sin override usa la duración del servicio (45 min)", :aggregate_failures do
      open_hours
      Appointments::BranchServiceOverride.delete_all

      expect(local_starts(availability)).to eq(%w[09:00 09:15 09:30 09:45 10:00 10:15 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15])
    end

    it "una sucursal sin horarios no ofrece huecos" do
      expect(availability).to eq([])
    end

    it "una ausencia de todo el día vacía la lista", :aggregate_failures do
      open_hours
      create(:time_off, professional:, starts_at: Time.utc(2026, 11, 16, 6), ends_at: Time.utc(2026, 11, 17, 6))

      expect(availability).to eq([])
    end

    it "una ausencia (de la persona, en cualquier sucursal) bloquea su tramo" do
      open_hours
      create(:time_off, professional:, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 17))

      expect(local_starts(availability)).to eq(%w[09:00 09:15 09:30 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
    end
  end

  describe "citas que bloquean" do
    before { open_hours }

    it "una cita del mismo profesional en OTRA sucursal bloquea (agenda única)" do
      create(:appointment, professional:, branch: second_branch, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30))

      expect(local_starts(availability)).not_to include("10:00", "10:15")
    end

    it "una cita de OTRO profesional no bloquea" do
      other = create(:professional, company:)
      create(:appointment, professional: other, branch:, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30))

      expect(local_starts(availability)).to include("10:00", "10:15")
    end

    it "una cita cancelada no bloquea y una no_show sí", :aggregate_failures do
      book(16, status: "cancelled")
      expect(local_starts(availability)).to include("10:00")

      book(17, status: "no_show")
      expect(local_starts(availability)).to include("10:00")
      expect(local_starts(availability)).not_to include("11:00")
    end

    it "una cita reprogramada no bloquea y una completada sí", :aggregate_failures do
      book(16, status: "rescheduled")
      expect(local_starts(availability)).to include("10:00")

      book(16, status: "completed")
      expect(local_starts(availability)).not_to include("10:00")
    end

    it "una cita que empieza antes del rango pero lo cruza bloquea (borde de zona)", :aggregate_failures do
      create(:appointment, professional:, branch:, starts_at: Time.utc(2026, 11, 16, 14), ends_at: Time.utc(2026, 11, 16, 15, 30))

      expect(local_starts(availability)).to eq(%w[09:30 09:45 10:00 10:15 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
    end
  end

  describe "settings" do
    it "los de la sucursal ganan a los de la empresa", :aggregate_failures do
      open_hours
      Modules::UpdateSettings.call(company:, key: "appointments", settings: { "slot_step_minutes" => 60 })
      expect(local_starts(availability)).to eq(%w[09:00 10:00 11:00 12:00])

      Modules::UpdateSettings.call(company:, key: "appointments", settings: { "slot_step_minutes" => 30 }, branch:)
      expect(local_starts(availability)).to eq(%w[09:00 09:30 10:00 10:30 11:00 11:30 12:00 12:30])
    end

    it "con anticipación mínima de 120 min y las 10:00 locales, el primer hueco de hoy es >= 12:00 (now por defecto)", :aggregate_failures do
      open_hours

      travel_to(Time.utc(2026, 11, 16, 16)) do
        slots = described_class.call(company:, branch:, service:, professional:, from_date: monday, to_date: monday)

        expect(local_starts(slots)).to eq(%w[12:00 12:15 12:30])
      end
    end
  end

  describe "aislamiento (adversarial)" do
    def populate_other_company
      other_company = create(:company)
      other_branch = create(:branch, company: other_company)
      other_pro = create(:professional, company: other_company)
      create(:weekly_schedule, branch: other_branch, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      create(:professional_branch_assignment, professional: other_pro, branch: other_branch)
      create(:time_off, professional: other_pro, starts_at: Time.utc(2026, 11, 16, 6), ends_at: Time.utc(2026, 11, 17, 6))
      create(:appointment, professional: other_pro, branch: other_branch, starts_at: Time.utc(2026, 11, 16, 15), ends_at: Time.utc(2026, 11, 16, 19))
    end

    def populate_other_organization
      with_tenant(create(:organization)) do
        foreign_company = create(:company)
        create(:appointment, professional: create(:professional, company: foreign_company), branch: create(:branch, company: foreign_company),
                             starts_at: Time.utc(2026, 11, 16, 15), ends_at: Time.utc(2026, 11, 16, 19))
      end
    end

    it "los datos de otra empresa y de otra organización no influyen", :aggregate_failures do
      open_hours
      book(16)
      baseline = availability

      populate_other_company
      populate_other_organization

      expect(baseline).not_to be_empty
      expect(availability).to eq(baseline)
    end
  end

  describe "elegibilidad" do
    def errors_of(**overrides)
      availability(**overrides)
      nil
    rescue Appointments::Availability::InvalidRequest => error
      error.errors
    end

    it "un profesional pausado es inactivo" do
      professional.update!(active: false)

      expect(errors_of).to eq([ { field: :professional_id, code: :inactive } ])
    end

    it "un profesional archivado es inactivo" do
      professional.update!(archived_at: Time.current)

      expect(errors_of).to eq([ { field: :professional_id, code: :inactive } ])
    end

    it "un profesional no asignado a la sucursal no está asignado" do
      unassigned = create(:professional, company:)
      create(:professional_service, professional: unassigned, service:)

      expect(errors_of(professional: unassigned)).to eq([ { field: :professional_id, code: :not_assigned } ])
    end

    it "un servicio inactivo o archivado" do
      service.update!(active: false)
      expect(errors_of).to eq([ { field: :service_id, code: :inactive } ])

      service.update!(active: true, archived_at: Time.current)
      expect(errors_of).to eq([ { field: :service_id, code: :inactive } ])
    end

    it "un profesional que no presta el servicio" do
      other_service = create(:service, company:)

      expect(errors_of(service: other_service)).to eq([ { field: :service_id, code: :not_provided } ])
    end

    it "un rango invertido o de más de 31 días es inválido, uno de 31 días no", :aggregate_failures do
      expected = [ { field: :to, code: :invalid_range } ]

      expect(errors_of(from_date: monday, to_date: monday - 1)).to eq(expected)
      expect(errors_of(from_date: monday, to_date: monday + 31)).to eq(expected)
      expect(errors_of(from_date: monday, to_date: monday + 30)).to be_nil
    end

    it "acumula todos los errores a la vez", :aggregate_failures do
      professional.update!(active: false)
      service.update!(active: false)

      expect(errors_of(from_date: monday, to_date: monday - 1)).to contain_exactly(
        { field: :professional_id, code: :inactive }, { field: :service_id, code: :inactive }, { field: :to, code: :invalid_range }
      )
    end
  end
end

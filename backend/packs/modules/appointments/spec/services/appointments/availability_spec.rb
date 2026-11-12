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
    described_class.call(company:, branch:, services: [ service ], professional:, from_date: monday, to_date: monday, now: long_before, **overrides).slots
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

  describe "horarios del profesional en otra sucursal" do
    it "las franjas del profesional en OTRA sucursal no abren huecos en esta", :aggregate_failures do
      create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "18:00")
      create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      create(:weekly_schedule, branch: second_branch, professional:, weekday: 1, starts_at_local: "14:00", ends_at_local: "18:00")

      expect(local_starts(availability)).to eq(%w[09:00 09:15 09:30 09:45 10:00 10:15 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
    end
  end

  describe "varios días con citas y ausencias" do
    before do
      (1..5).each { open_hours(weekday: it) }
      14.times do |day|
        start = Time.utc(2026, 11, 16, 16) + day.days
        create(:appointment, professional:, branch:, starts_at: start, ends_at: start + 30.minutes)
        create(:time_off, professional:, starts_at: start + 1.hour, ends_at: start + 90.minutes)
      end
    end

    it "devuelve huecos que respetan las citas y ausencias repartidas en las dos semanas", :aggregate_failures do
      slots = availability(to_date: monday + 13)

      busy = Appointments::Appointment.pluck(:blocks_from, :blocks_to) + Appointments::TimeOff.pluck(:starts_at, :ends_at)
      expect(slots).not_to be_empty
      expect(slots).to all(satisfy { |slot| busy.none? { |from, to| slot.starts_at < to && from < slot.ends_at } })
    end
  end

  describe "citas que bloquean" do
    before { open_hours }

    it "una cita del mismo profesional en OTRA sucursal bloquea (agenda única)" do
      create(:appointment, professional:, branch: second_branch, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30))

      expect(local_starts(availability)).to eq(%w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
    end

    it "una cita cuyo bloqueo es más ancho que sus horas (relleno) quita también los inicios del relleno" do
      create(:appointment, professional:, branch:, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30),
                           blocks_from: Time.utc(2026, 11, 16, 15, 45), blocks_to: Time.utc(2026, 11, 16, 16, 45))

      expect(local_starts(availability)).to eq(%w[09:00 09:15 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
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
        slots = described_class.call(company:, branch:, services: [ service ], professional:, from_date: monday, to_date: monday).slots

        expect(local_starts(slots)).to eq(%w[12:00 12:15 12:30])
      end
    end
  end

  describe "aislamiento (adversarial)" do
    # Absences and appointments of someone else's professional exactly where the requested professional is open and free.
    def occupy_every_open_hour(professional:, branch:)
      create(:time_off, professional:, starts_at: Time.utc(2026, 11, 16, 15), ends_at: Time.utc(2026, 11, 16, 16))
      [ 16, 17, 18 ].each do |hour|
        create(:appointment, professional:, branch:, starts_at: Time.utc(2026, 11, 16, hour), ends_at: Time.utc(2026, 11, 16, hour, 30))
      end
    end

    def populate_other_company
      other_company = create(:company)
      other_branch = create(:branch, company: other_company)
      other_pro = create(:professional, company: other_company)
      create(:weekly_schedule, branch: other_branch, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      create(:professional_branch_assignment, professional: other_pro, branch: other_branch)
      create(:weekly_schedule, branch: other_branch, professional: other_pro, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      occupy_every_open_hour(professional: other_pro, branch: other_branch)
    end

    def populate_other_organization
      with_tenant(create(:organization)) do
        foreign_company = create(:company)
        foreign_branch = create(:branch, company: foreign_company)
        foreign_pro = create(:professional, company: foreign_company)
        create(:professional_branch_assignment, professional: foreign_pro, branch: foreign_branch)
        occupy_every_open_hour(professional: foreign_pro, branch: foreign_branch)
      end
    end

    it "los datos de otra empresa y de otra organización no influyen", :aggregate_failures do
      open_hours
      book(16)
      expected = %w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30]
      expect(local_starts(availability)).to eq(expected)

      populate_other_company
      populate_other_organization

      expect(local_starts(availability)).to eq(expected)
    end
  end

  describe "elegibilidad" do
    def errors_of(**overrides)
      availability(**overrides)
      nil
    rescue Appointments::Availability::InvalidRequest => error
      error.errors
    end

    it "una sucursal inactiva está cerrada" do
      branch.update!(status: "inactive")

      expect(errors_of).to eq([ { field: :branch_id, code: :inactive } ])
    end

    context "con datos de una empresa hermana de la misma organización" do
      def sibling = @sibling ||= create_in(organization, :company)

      it "un profesional de otra empresa devuelve exactamente wrong_company y ningún otro error" do
        foreign = create_in(organization, :professional, company: sibling)

        expect(errors_of(professional: foreign)).to eq([ { field: :professional_id, code: :wrong_company } ])
      end

      it "un servicio de otra empresa se rechaza" do
        foreign = create_in(organization, :service, company: sibling)

        expect(errors_of(services: [ foreign ])).to eq([ { field: :service_ids, code: :wrong_company } ])
      end

      it "una sucursal de otra empresa se rechaza" do
        foreign = create_in(organization, :branch, company: sibling)

        expect(errors_of(branch: foreign)).to eq([ { field: :branch_id, code: :wrong_company } ])
      end
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
      expect(errors_of).to eq([ { field: :service_ids, code: :inactive } ])

      service.update!(active: true, archived_at: Time.current)
      expect(errors_of).to eq([ { field: :service_ids, code: :inactive } ])
    end

    it "un profesional que no presta el servicio" do
      other_service = create(:service, company:)

      expect(errors_of(services: [ other_service ])).to eq([ { field: :service_ids, code: :not_provided } ])
    end

    it "un rango invertido o de más de 31 días es inválido, uno de 31 días no", :aggregate_failures do
      expected = [ { field: :to, code: :invalid_range } ]

      expect(errors_of(from_date: monday, to_date: monday - 1)).to eq(expected)
      expect(errors_of(from_date: monday, to_date: monday + 31)).to eq(expected)
      expect(errors_of(from_date: monday, to_date: monday + 30)).to be_nil
    end

    it "un `from` anterior a ayer en la hora local de la sucursal es demasiado antiguo, ayer no", :aggregate_failures do
      now = Time.utc(2026, 11, 16, 5)

      expect(errors_of(from_date: Date.new(2026, 11, 13), to_date: monday, now:)).to eq([ { field: :from, code: :too_early } ])
      expect(errors_of(from_date: Date.new(2026, 11, 14), to_date: monday, now:)).to be_nil
    end

    it "acumula todos los errores a la vez", :aggregate_failures do
      professional.update!(active: false)
      service.update!(active: false)

      expect(errors_of(from_date: monday, to_date: monday - 1)).to contain_exactly(
        { field: :professional_id, code: :inactive }, { field: :service_ids, code: :inactive }, { field: :to, code: :invalid_range }
      )
    end
  end

  describe "elegibilidad de la lista de servicios" do
    def errors_of(**overrides)
      availability(**overrides)
      nil
    rescue Appointments::Availability::InvalidRequest => error
      error.errors
    end

    def provided_service(**attributes)
      create(:service, company:).tap do |own|
        create(:professional_service, professional:, service: own)
        own.update!(attributes)
      end
    end

    it "una lista vacía es blank" do
      expect(errors_of(services: [])).to eq([ { field: :service_ids, code: :blank } ])
    end

    it "seis servicios son demasiados y cinco no", :aggregate_failures do
      six = Array.new(6) { provided_service }

      expect(errors_of(services: six)).to eq([ { field: :service_ids, code: :too_many } ])
      expect(errors_of(services: six.first(5))).to be_nil
    end

    it "un servicio repetido es duplicated" do
      expect(errors_of(services: [ service, service ])).to eq([ { field: :service_ids, code: :duplicated } ])
    end

    it "un servicio inactivo entre varios se reporta una sola vez", :aggregate_failures do
      second = provided_service(active: false)
      third = provided_service(archived_at: Time.current)

      expect(errors_of(services: [ service, second, third ])).to eq([ { field: :service_ids, code: :inactive } ])
    end

    it "un profesional que no presta UNO de los dos servicios es not_provided" do
      unprovided = create(:service, company:)

      expect(errors_of(services: [ service, unprovided ])).to eq([ { field: :service_ids, code: :not_provided } ])
    end

    it "adversarial: un servicio de otra empresa en la posición 2 devuelve solo wrong_company", :aggregate_failures do
      sibling = create_in(organization, :company)
      foreign = create_in(organization, :service, company: sibling)
      professional.update!(active: false)

      expect(errors_of(services: [ service, foreign ], from_date: monday, to_date: monday - 1)).to eq([ { field: :service_ids, code: :wrong_company } ])
    end

    it "una combinación que pide dos tipos de recurso es multiple_resource_kinds", :aggregate_failures do
      other = provided_service
      create(:service_resource_requirement, service:, kind: "room")
      create(:service_resource_requirement, service: other, kind: "chair")

      expect(errors_of(services: [ service, other ])).to eq([ { field: :service_ids, code: :multiple_resource_kinds } ])
      expect(errors_of(services: [ service ])).to be_nil
    end

    it "con :any no se exige que nadie preste los servicios (no es error)" do
      expect(errors_of(professional: :any, services: [ create(:service, company:) ])).to be_nil
    end

    it "un profesional concreto que no es de la empresa sigue dando wrong_company con una lista", :aggregate_failures do
      foreign = create_in(organization, :professional, company: create_in(organization, :company))

      expect(errors_of(professional: foreign)).to eq([ { field: :professional_id, code: :wrong_company } ])
    end
  end

  describe "varios servicios, precio y buffers" do
    def result(**overrides)
      described_class.call(company:, branch:, services: [ service ], professional:, from_date: monday, to_date: monday, now: long_before, **overrides)
    end

    # barba 20 min (price 5_000) then corte 30 min with a 10 min cleanup (price 15_000); order is the one asked.
    def beard_and_cut
      beard = create(:service, company:, duration_minutes: 20, price_minor: 5_000)
      cut = create(:service, company:, duration_minutes: 30, price_minor: 15_000, buffer_after_minutes: 10)
      [ beard, cut ].each { |own| create(:professional_service, professional:, service: own) }
      [ beard, cut ]
    end

    before { open_hours }

    it "barba + corte: duración 50, buffers de los bordes, precio 20_000 y la moneda de la empresa", :aggregate_failures do
      outcome = result(services: beard_and_cut)

      expect(outcome.duration_minutes).to eq(50)
      expect(outcome.buffer_before_minutes).to eq(0)
      expect(outcome.buffer_after_minutes).to eq(10)
      expect(outcome.price_minor).to eq(20_000)
      expect(outcome.currency).to eq(company.currency)
      expect(outcome.slots.map { it.ends_at - it.starts_at }.uniq).to eq([ 50.minutes.to_i ])
    end

    it "el bloque de 60 min cabe entero en el horario: con 9-13 el último inicio es 12:00 (12:15 se saldría)", :aggregate_failures do
      outcome = result(services: beard_and_cut)

      expect(local_starts(outcome.slots).last).to eq("12:00")
      expect(local_starts(outcome.slots).first).to eq("09:00")
    end

    it "el override de precio de la sucursal gana al base solo en esa sucursal", :aggregate_failures do
      other_branch = second_branch
      create(:branch_service_override, service:, branch: other_branch, duration_minutes: nil, price_minor: 12_345)
      Appointments::BranchServiceOverride.find_by!(service_id: service.id, branch_id: branch.id).update!(price_minor: 7_000)

      expect(result.price_minor).to eq(7_000)
      expect(result(branch: other_branch).price_minor).to eq(12_345)
    end

    it "sin override de precio ni de duración usa los del servicio", :aggregate_failures do
      Appointments::BranchServiceOverride.delete_all

      outcome = result

      expect([ outcome.price_minor, outcome.duration_minutes ]).to eq([ 20_000, 45 ])
    end

    it "los huecos llevan el id del profesional y resource_id nulo sin requisito de recurso", :aggregate_failures do
      outcome = result

      expect(outcome.slots.map(&:professional_id).uniq).to eq([ professional.id ])
      expect(outcome.slots.map(&:resource_id).uniq).to eq([ nil ])
    end
  end

  describe ":any" do
    def other = @other ||= create(:professional, company:)

    before do
      open_hours
      create(:professional_branch_assignment, professional: other, branch:)
      create(:professional_service, professional: other, service:)
      create(:weekly_schedule, branch:, professional: other, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    end

    def any_slots(**overrides) = availability(professional: :any, **overrides)

    def at_ten(slots) = slots.find { it.starts_at == Time.utc(2026, 11, 16, 16) }

    it "dos libres a las 10:00: gana el de menor id sin citas, y quien tiene menos citas ese día si difieren", :aggregate_failures do
      lowest = [ professional, other ].min_by(&:id)
      highest = [ professional, other ].max_by(&:id)
      expect(at_ten(any_slots).professional_id).to eq(lowest.id)

      create(:appointment, professional: lowest, branch:, starts_at: Time.utc(2026, 11, 16, 14), ends_at: Time.utc(2026, 11, 16, 14, 30))

      expect(at_ten(any_slots).professional_id).to eq(highest.id)
    end

    it "la carga cuenta las citas del día local en cualquier sucursal (agenda única)", :aggregate_failures do
      lowest, highest = [ professional, other ].sort_by(&:id)
      create(:appointment, professional: lowest, branch: second_branch, starts_at: Time.utc(2026, 11, 16, 14), ends_at: Time.utc(2026, 11, 16, 14, 30))

      expect(at_ten(any_slots).professional_id).to eq(highest.id)
    end

    it "una cita de otro día local no cuenta para la carga", :aggregate_failures do
      lowest = [ professional, other ].min_by(&:id)
      create(:appointment, professional: lowest, branch:, starts_at: Time.utc(2026, 11, 17, 14), ends_at: Time.utc(2026, 11, 17, 14, 30))

      expect(at_ten(any_slots).professional_id).to eq(lowest.id)
    end

    it "un profesional que no presta todos los servicios queda fuera (adversarial: presta 1 de 2)", :aggregate_failures do
      second = create(:service, company:)
      create(:professional_service, professional:, service: second)

      slots = any_slots(services: [ service, second ])

      expect(slots.map(&:professional_id).uniq).to eq([ professional.id ])
      expect(slots).not_to be_empty
    end

    it "sin elegibles el resultado es vacío y no un error", :aggregate_failures do
      orphan = create(:service, company:)

      expect(availability(professional: :any, services: [ orphan ])).to eq([])
    end

    it "un profesional pausado o archivado no entra en :any", :aggregate_failures do
      other.update!(active: false)
      professional.update!(archived_at: Time.current)

      expect(any_slots).to eq([])
    end
  end

  describe "recursos" do
    def add_open_professional
      other = create(:professional, company:)
      create(:professional_branch_assignment, professional: other, branch:)
      create(:professional_service, professional: other, service:)
      create(:weekly_schedule, branch:, professional: other, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    end

    def room = @room ||= create(:resource, branch:, kind: "room")

    before do
      open_hours
      create(:service_resource_requirement, service:, kind: "room")
      create(:resource, branch: second_branch, kind: "room")
    end

    it "sin ninguna sala el servicio que la pide no tiene huecos" do
      expect(availability).to eq([])
    end

    it "una sala de la sucursal sigue el horario de la sucursal y sale en el hueco (resource_id)", :aggregate_failures do
      room
      slots = availability

      expect(slots.map(&:resource_id).uniq).to eq([ room.id ])
      expect(local_starts(slots).first).to eq("09:00")
    end

    it "la única sala ausente a las 11:00 (17:00Z) quita ese tramo aunque haya dos profesionales libres", :aggregate_failures do
      create(:time_off, resource: room, starts_at: Time.utc(2026, 11, 16, 17), ends_at: Time.utc(2026, 11, 16, 18))
      add_open_professional

      slots = availability(professional: :any)

      expect(local_starts(slots)).not_to include("11:00", "11:15", "11:30", "10:45")
      expect(local_starts(slots)).to include("10:15", "12:00")
    end

    it "la única sala ocupada por una cita a las 11:00 (17:00Z) quita ese tramo aunque los profesionales estén libres", :aggregate_failures do
      add_open_professional
      busy_with = create(:professional, company:)
      create(:appointment, professional: busy_with, branch:, resource: room, starts_at: Time.utc(2026, 11, 16, 17),
                           ends_at: Time.utc(2026, 11, 16, 17, 30))

      slots = availability(professional: :any)

      expect(local_starts(slots)).not_to include("11:00", "11:15", "10:45")
      expect(local_starts(slots)).to include("10:15", "11:30", "12:00")
    end

    it "una cita cancelada en la sala no la ocupa" do
      add_open_professional
      create(:appointment, professional: create(:professional, company:), branch:, resource: room, status: "cancelled",
                           starts_at: Time.utc(2026, 11, 16, 17), ends_at: Time.utc(2026, 11, 16, 17, 30))

      expect(local_starts(availability(professional: :any))).to include("11:00")
    end

    it "una sala archivada, pausada o de otra sucursal no se ofrece", :aggregate_failures do
      room.update!(archived_at: Time.current)
      create(:resource, branch:, kind: "room", active: false)

      expect(availability).to eq([])
    end

    it "una sala de otro tipo no satisface el requisito" do
      create(:resource, branch:, kind: "chair")

      expect(availability).to eq([])
    end

    it "con dos salas se asigna la de menor id", :aggregate_failures do
      first = create(:resource, branch:, kind: "room")
      second = create(:resource, branch:, kind: "room")

      expect(availability.map(&:resource_id).uniq).to eq([ [ first, second ].min_by(&:id).id ])
    end
  end
end

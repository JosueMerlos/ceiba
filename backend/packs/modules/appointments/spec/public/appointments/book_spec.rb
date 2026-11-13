require "rails_helper"

RSpec.describe Appointments::Book do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(organization, :professional, company:) }

  def customer = @customer ||= create_in(organization, :customer, company:)
  def actor = @actor ||= Struct.new(:actor_type, :id).new("user", SecureRandom.uuid)

  # Monday. The branch is in America/Managua (UTC-6, no DST), so 10:00 local is 16:00Z; the hours are 09:00-13:00 local.
  def starts_at = Time.utc(2026, 11, 16, 16)
  def now = Time.utc(2026, 11, 1)

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    make_bookable(professional)
  end

  def make_bookable(person, offered: service)
    create(:professional_branch_assignment, professional: person, branch:)
    create(:professional_service, professional: person, service: offered)
    create(:weekly_schedule, branch:, professional: person, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    person
  end

  def choice(person) = Appointments::Availability::ProfessionalChoice.of(person)

  def book(**overrides)
    described_class.call(company:, branch:, customer_id: customer.id, services: [ service ], professional: choice(professional), starts_at:,
                         source: "panel", actor:, now:, **overrides)
  end

  def booked_events = Events::OutboxEvent.where(name: "appointments.appointment_booked.v1")
  def audits = Audit::Event.where(action: "appointments.appointment.booked")
  def lines_of(appointment) = Appointments::AppointmentService.where(appointment_id: appointment.id).order(:position)

  def untouched
    [ Appointments::Appointment.count, Appointments::AppointmentService.count, booked_events.count, audits.count ]
  end

  def with_chairs(count)
    create(:service_resource_requirement, service:, kind: "chair")
    Array.new(count) { create(:resource, branch:, kind: "chair") }.sort_by(&:id)
  end

  def errors_of(**overrides)
    book(**overrides)
    raise "expected InvalidBooking"
  rescue Appointments::InvalidBooking => error
    error.errors
  end

  describe "caso feliz" do
    # beard: 20 min, 5_000, 5 min buffer before; cut: 30 min, 15_000, 10 min buffer after; the branch lowers the cut's price to 12_000.
    def beard = @beard ||= create(:service, company:, duration_minutes: 20, price_minor: 5_000, buffer_before_minutes: 5)
    def cut = @cut ||= create(:service, company:, duration_minutes: 30, price_minor: 15_000, buffer_after_minutes: 10)

    before do
      [ beard, cut ].each { |own| create(:professional_service, professional:, service: own) }
      create(:branch_service_override, service: cut, branch:, duration_minutes: nil, price_minor: 12_000)
    end

    def book_both(**overrides) = book(services: [ beard, cut ], **overrides)

    it "guarda la cita, sus dos líneas con el precio efectivo y el bloque con los buffers de los bordes", :aggregate_failures do
      appointment = book_both(notes: "Alérgico al látex")

      expect(appointment).to be_persisted
      expect(appointment.reload).to have_attributes(
        company_id: company.id, branch_id: branch.id, professional_id: professional.id, customer_id: customer.id, resource_id: nil,
        starts_at: starts_at, ends_at: starts_at + 50.minutes, blocks_from: starts_at - 5.minutes, blocks_to: starts_at + 60.minutes,
        status: "scheduled", source: "panel", notes: "Alérgico al látex", lock_version: 0, rescheduled_from_id: nil,
        created_by_type: "user", created_by_id: actor.id
      )
      expect(lines_of(appointment).map { it.attributes.symbolize_keys.slice(:service_id, :position, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency) }).to eq([
        { service_id: beard.id, position: 0, duration_minutes: 20, buffer_before_minutes: 5, buffer_after_minutes: 0, price_minor: 5_000, currency: company.currency },
        { service_id: cut.id, position: 1, duration_minutes: 30, buffer_before_minutes: 0, buffer_after_minutes: 10, price_minor: 12_000, currency: company.currency }
      ])
    end

    it "la suma de las líneas es el precio y la duración del plan", :aggregate_failures do
      plan = Appointments::Availability.call(company:, branch:, services: [ beard, cut ], professional: choice(professional), from_date: starts_at.to_date,
                                             to_date: starts_at.to_date, now:).plan
      lines = lines_of(book_both)

      expect(lines.sum(&:price_minor)).to eq(plan.price_minor)
      expect(lines.sum(&:duration_minutes)).to eq(plan.duration_minutes)
    end

    it "cambiar el precio del servicio y el override después de reservar no altera las líneas" do
      appointment = book_both
      cut.update!(price_minor: 1)
      beard.update!(price_minor: 2)
      Appointments::BranchServiceOverride.find_by!(service_id: cut.id).update!(price_minor: 3)

      expect(lines_of(appointment).pluck(:price_minor)).to eq([ 5_000, 12_000 ])
    end

    it "sin actor ni principal la cita queda creada por el sistema", :aggregate_failures do
      appointment = book_both(actor: nil)

      expect([ appointment.created_by_type, appointment.created_by_id ]).to eq([ "system", nil ])
      expect(audits.first).to have_attributes(actor_type: "system", actor_id: nil)
    end

    it "el actor por defecto es Current.principal" do
      Current.principal = actor
      appointment = described_class.call(company:, branch:, customer_id: customer.id, services: [ service ], professional: choice(professional), starts_at:,
                                         source: "panel", now:)

      expect([ appointment.created_by_type, appointment.created_by_id ]).to eq([ "user", actor.id ])
    ensure
      Current.principal = nil
    end
  end

  describe "hueco ocupado" do
    it "otra cita en el hueco: SlotUnavailable, sin filas, sin evento y sin auditoría", :aggregate_failures do
      create(:appointment, professional:, branch:, customer:, starts_at:)
      before = untouched

      expect { book }.to raise_error(Appointments::SlotUnavailable)
      expect(untouched).to eq(before)
    end

    it "una cita cancelada de 10 a 11 no impide reservar de 10 a 11" do
      create(:appointment, professional:, branch:, customer:, starts_at:, ends_at: starts_at + 1.hour, status: "cancelled")

      expect(book).to be_persisted
    end

    it "un hueco que el motor ya no ofrece (una ausencia nueva, como una caché vieja): SlotUnavailable, no 422", :aggregate_failures do
      create(:time_off, professional:, starts_at: starts_at - 1.hour, ends_at: starts_at + 2.hours)

      expect { book }.to raise_error(Appointments::SlotUnavailable)
      expect(untouched).to eq([ 0, 0, 0, 0 ])
    end

    it "un horario que cambió: SlotUnavailable" do
      Appointments::WeeklySchedule.where(professional_id: professional.id).delete_all

      expect { book }.to raise_error(Appointments::SlotUnavailable)
    end

    it "fuera de la rejilla de slot_step_minutes: SlotUnavailable" do
      expect { book(starts_at: starts_at + 7.minutes) }.to raise_error(Appointments::SlotUnavailable)
    end
  end

  describe "recurso" do
    def other = @other ||= make_bookable(create(:professional, company:))

    it "el recurso sale del hueco revalidado y se guarda y se publica", :aggregate_failures do
      chair = with_chairs(1).first

      appointment = book

      expect(appointment.reload.resource_id).to eq(chair.id)
      expect(booked_events.last.payload["resource_id"]).to eq(chair.id)
    end

    it "mismo recurso con otro profesional y el único sillón ocupado: el motor no ofrece el hueco y sale SlotUnavailable" do
      chair = with_chairs(1).first
      create(:appointment, professional: other, branch:, customer:, resource: chair, starts_at:)

      expect { book }.to raise_error(Appointments::SlotUnavailable)
    end
  end

  describe "entrada inválida" do
    it "un servicio inactivo es InvalidRequest (422), no un conflicto", :aggregate_failures do
      service.update!(active: false)

      expect { book }.to raise_error(Appointments::Availability::InvalidRequest) { |error| expect(error.errors).to include(field: :service_ids, code: :inactive) }
    end

    it "un profesional no asignado a la sucursal es InvalidRequest" do
      unassigned = create(:professional, company:)
      create(:professional_service, professional: unassigned, service:)

      expect { book(professional: choice(unassigned)) }.to raise_error(Appointments::Availability::InvalidRequest) { |error| expect(error.errors).to include(field: :professional_id, code: :not_assigned) }
    end

    it "un cliente archivado: InvalidBooking en customer_id", :aggregate_failures do
      Customers::Archive.call(customer:)

      expect(errors_of).to eq([ { field: :customer_id, code: :invalid } ])
      expect(untouched).to eq([ 0, 0, 0, 0 ])
    end

    it "un cliente de otra empresa de la organización: InvalidBooking en customer_id" do
      sibling_customer = create(:customer, company: create(:company))

      expect(errors_of(customer_id: sibling_customer.id)).to eq([ { field: :customer_id, code: :invalid } ])
    end

    it "un customer_id que no existe: InvalidBooking en customer_id" do
      expect(errors_of(customer_id: SecureRandom.uuid)).to eq([ { field: :customer_id, code: :invalid } ])
    end

    it "un origen desconocido, notas de más de 500 caracteres y sin starts_at se reportan juntos" do
      expect { book(starts_at: nil, source: "otro", notes: "x" * 501) }.to raise_error(Appointments::InvalidBooking) do |error|
        expect(error.errors).to contain_exactly({ field: :source, code: :invalid }, { field: :notes, code: :too_long }, { field: :starts_at, code: :blank })
      end
    end

    it "notas de exactamente 500 caracteres se aceptan" do
      expect(book(notes: "x" * 500).reload.notes).to eq("x" * 500)
    end

    it "el profesional any no se acepta: InvalidBooking en professional_id (any_not_allowed)" do
      expect(errors_of(professional: Appointments::Availability::ProfessionalChoice.any)).to eq([ { field: :professional_id, code: :any_not_allowed } ])
    end
  end

  describe "ventana de reserva según el origen" do
    it "una cita del panel puede reservarse dentro de la anticipación mínima y más allá de la máxima", :aggregate_failures do
      expect(book(now: starts_at - 30.minutes)).to be_persisted
      expect(book(starts_at: starts_at + 1.hour, now: Time.utc(2026, 8, 1))).to be_persisted
    end

    it "una reserva pública sí respeta la anticipación mínima y la máxima", :aggregate_failures do
      expect { book(source: "public_booking", now: starts_at - 30.minutes) }.to raise_error(Appointments::SlotUnavailable)
      expect { book(source: "public_booking", now: Time.utc(2026, 8, 1)) }.to raise_error(Appointments::SlotUnavailable)
    end

    it "el panel tampoco reserva un bloque que empieza antes de ahora" do
      expect { book(now: starts_at + 5.minutes) }.to raise_error(Appointments::SlotUnavailable)
    end
  end

  describe "evento y auditoría" do
    it "publica appointment_booked.v1 con solo ids y horas, sin notas ni datos del cliente", :aggregate_failures do
      appointment = book(notes: "Dolor de muela")

      expect(booked_events.count).to eq(1)
      payload = booked_events.first.payload
      expect(payload.keys).to match_array(%w[appointment_id branch_id professional_id customer_id resource_id starts_at ends_at service_ids source rescheduled_from_id])
      expect(payload.except("starts_at", "ends_at")).to eq(
        "appointment_id" => appointment.id, "branch_id" => branch.id, "professional_id" => professional.id, "customer_id" => customer.id,
        "resource_id" => nil, "service_ids" => [ service.id ], "source" => "panel", "rescheduled_from_id" => nil
      )
      expect([ Time.iso8601(payload["starts_at"]), Time.iso8601(payload["ends_at"]) ]).to eq([ starts_at, starts_at + 30.minutes ])
      expect(payload.to_s).not_to include("Dolor de muela")
    end

    it "audita la reserva con el actor, el sujeto y las notas filtradas", :aggregate_failures do
      appointment = book(notes: "Dolor de muela")

      audit = audits.sole
      expect(audit).to have_attributes(auditable_type: "Appointments::Appointment", auditable_id: appointment.id, actor_type: "user", actor_id: actor.id)
      expect(audit.after).to include("professional_id" => professional.id, "customer_id" => customer.id, "status" => "scheduled", "notes" => "[FILTERED]")
      expect(audit.after.to_s).not_to include("Dolor de muela")
    end

    it "si la auditoría falla no queda la cita, ni sus líneas ni el evento", :aggregate_failures do
      allow(Audit).to receive(:record).and_raise(RuntimeError, "audit down")

      expect { book }.to raise_error(RuntimeError, "audit down")
      expect(untouched).to eq([ 0, 0, 0, 0 ])
    end
  end

  describe "reprogramación" do
    it "guarda rescheduled_from_id y lo publica", :aggregate_failures do
      original = create(:appointment, professional:, branch:, customer:, starts_at: starts_at + 2.hours, status: "rescheduled")

      appointment = book(rescheduled_from: original)

      expect(appointment.reload.rescheduled_from_id).to eq(original.id)
      expect(booked_events.last.payload["rescheduled_from_id"]).to eq(original.id)
    end
  end
end

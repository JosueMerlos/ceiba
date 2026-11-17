require "rails_helper"

RSpec.describe Appointments::Reschedule do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(organization, :professional, company:) }

  def customer = @customer ||= create_in(organization, :customer, company:)
  def actor = @actor ||= Struct.new(:actor_type, :id).new("user", SecureRandom.uuid)

  # Monday 16 Nov 2026 in America/Managua (UTC-6): 10:00 local is 16:00Z; the hours are 09:00-13:00 local.
  def ten = Time.utc(2026, 11, 16, 16)
  def now = Time.utc(2026, 11, 1)

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    make_bookable(professional)
  end

  def make_bookable(person)
    create(:professional_branch_assignment, professional: person, branch:)
    create(:professional_service, professional: person, service:)
    create(:weekly_schedule, branch:, professional: person, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    person
  end

  def choice(person) = Appointments::Availability::ProfessionalChoice.of(person)

  def book(starts_at: ten, person: professional, notes: "Trae su propio tinte")
    Appointments::Book.call(company:, branch:, customer_id: customer.id, services: [ service ], professional: choice(person), starts_at:,
                            source: "panel", notes:, actor:, now:)
  end

  def original = @original ||= book

  def reschedule(appointment = original, starts_at: ten + 1.hour, person: professional)
    described_class.call(appointment:, company:, branch:, starts_at:, professional: choice(person), source: "panel", actor:, now:)
  end

  def counts
    [ Appointments::Appointment.count, Appointments::AppointmentService.count, Events::OutboxEvent.count, Audit::Event.count ]
  end

  it "encadena: la original queda rescheduled y la nueva nace scheduled, enlazada, con el mismo cliente, servicios y notas", :aggregate_failures do
    moved = reschedule

    expect(original.reload).to have_attributes(status: "rescheduled", lock_version: 1)
    expect(moved.reload).to have_attributes(status: "scheduled", rescheduled_from_id: original.id, customer_id: customer.id,
                                            professional_id: professional.id, starts_at: ten + 1.hour, notes: "Trae su propio tinte",
                                            source: "panel", created_by_type: "user", created_by_id: actor.id)
    expect(moved.services_snapshot.map(&:service_id)).to eq([ service.id ])
  end

  it "publica un solo evento de reprogramación con la cita nueva y la reserva enlazada, y audita una vez", :aggregate_failures do
    original
    moved = reschedule

    rescheduled = Events::OutboxEvent.where(name: "appointments.appointment_rescheduled.v1").sole.payload
    expect(rescheduled).to include("appointment_id" => original.id, "new_appointment_id" => moved.id, "from_status" => "scheduled")
    expect(Events::OutboxEvent.where(name: "appointments.appointment_booked.v1").map { it.payload["rescheduled_from_id"] })
      .to contain_exactly(nil, original.id)
    audit = Audit::Event.where(action: "appointments.appointment.rescheduled").sole
    expect(audit).to have_attributes(auditable_id: original.id, before: { "status" => "scheduled" },
                                     after: { "status" => "rescheduled", "new_appointment_id" => moved.id })
  end

  it "mueve una cita a un hueco que se solapa con ella misma, porque la original deja de bloquear antes de reservar" do
    expect(reschedule(starts_at: ten + 15.minutes).starts_at).to eq(ten + 15.minutes)
  end

  it "a un hueco ocupado es SlotUnavailable y lo revierte todo: la original sigue scheduled y no queda nada nuevo", :aggregate_failures do
    other = create(:customer, company:)
    Appointments::Book.call(company:, branch:, customer_id: other.id, services: [ service ], professional: choice(professional),
                            starts_at: ten + 1.hour, source: "panel", actor:, now:)
    original
    before = counts

    expect { reschedule(starts_at: ten + 1.hour) }.to raise_error(Appointments::SlotUnavailable)

    expect(original.reload).to have_attributes(status: "scheduled", lock_version: 0)
    expect(counts).to eq(before)
  end

  it "una original que ya terminó es InvalidTransition y no crea ninguna cita", :aggregate_failures do
    Appointments::Appointment.where(id: original.id).update_all(status: "completed")
    before = counts

    expect { reschedule }.to raise_error(Appointments::InvalidTransition)
    expect(counts).to eq(before)
  end

  it "puede cambiar de profesional" do
    other = make_bookable(create(:professional, company:))

    expect(reschedule(person: other).professional_id).to eq(other.id)
  end

  it "conserva el precio y la moneda de cada línea de la original aunque el catálogo cambió, con la duración actual", :aggregate_failures do
    original
    service.update!(price_minor: 35_000, duration_minutes: 45)

    moved = reschedule

    expect(moved.services_snapshot.map { [ it.price_minor, it.currency, it.duration_minutes ] }).to eq([ [ 20_000, "NIO", 45 ] ])
    expect(moved.ends_at).to eq(ten + 1.hour + 45.minutes)
    expect(Audit::Event.where(action: "appointments.appointment.booked", auditable_id: moved.id).sole.metadata)
      .to include("total_price_minor" => 20_000, "currency" => "NIO")
  end

  it "con varios servicios conserva el precio de cada uno por servicio, en su orden, y el total", :aggregate_failures do
    beard = create(:service, company:, duration_minutes: 20, price_minor: 5_000)
    create(:professional_service, professional:, service: beard)
    two = Appointments::Book.call(company:, branch:, customer_id: customer.id, services: [ beard, service ], professional: choice(professional),
                                  starts_at: ten, source: "panel", actor:, now:)
    beard.update!(price_minor: 9_000)
    service.update!(price_minor: 50_000)

    moved = reschedule(two)

    expect(moved.services_snapshot.map { [ it.service_id, it.position, it.price_minor ] })
      .to eq([ [ beard.id, 0, 5_000 ], [ service.id, 1, 20_000 ] ])
    expect(Audit::Event.where(action: "appointments.appointment.booked", auditable_id: moved.id).sole.metadata["total_price_minor"]).to eq(25_000)
  end

  it "con un servicio archivado desde la reserva no reprograma y la original sigue scheduled", :aggregate_failures do
    original
    service.update_columns(archived_at: now)

    expect { reschedule }.to raise_error(Appointments::Availability::InvalidRequest)
    expect(original.reload.status).to eq("scheduled")
  end

  it "rechaza una sucursal que no es la de la cita (error del llamador)" do
    other_branch = create(:branch, company:)

    expect { described_class.call(appointment: original, company:, branch: other_branch, starts_at: ten, professional: choice(professional), source: "panel", actor:, now:) }
      .to raise_error(ArgumentError, /branch/)
  end
end

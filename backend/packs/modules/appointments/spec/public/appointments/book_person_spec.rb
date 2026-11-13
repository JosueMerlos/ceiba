require "rails_helper"

# One person (professionals.user_id) with a record in two companies of the same organization: the engine only sees one company's
# agenda, so Book is the one that refuses a booking that overlaps the person's appointment in the other company.
RSpec.describe Appointments::Book do
  let(:organization) { create(:organization) }
  let(:company_a) { create_in(organization, :company) }
  let(:company_b) { create_in(organization, :company) }
  let!(:a) { setup_company(company_a, user_id: person.id) }
  let!(:b) { setup_company(company_b, user_id: person.id) }

  def person = @person ||= create(:user)
  def now = Time.utc(2026, 11, 1)
  # Monday, 10:00 local (America/Managua, UTC-6).
  def ten = Time.utc(2026, 11, 16, 16)

  around { |example| with_tenant(organization) { example.run } }

  # A branch, a service, a customer and a professional (optionally the person) of a company, bookable on Monday 09:00-13:00.
  def setup_company(company, user_id: nil)
    Modules::Enable.call(company:, key: "appointments")
    branch = create(:branch, company:)
    user_with_role("receptionist", organization, branch:, user: person) if user_id
    service = create(:service, company:, duration_minutes: 30)
    professional = create(:professional, company:, user_id:)
    create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create(:professional_branch_assignment, professional:, branch:)
    create(:professional_service, professional:, service:)
    create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    { company:, branch:, service:, professional:, customer: create(:customer, company:) }
  end

  def book_in(world, starts_at)
    described_class.call(company: world[:company], branch: world[:branch], customer_id: world[:customer].id, services: [ world[:service] ],
                         professional: Appointments::Availability::ProfessionalChoice.of(world[:professional]), starts_at:, source: "panel", now:)
  end

  def block_person_in_a(status: "scheduled")
    create(:appointment, professional: a[:professional], branch: a[:branch], customer: a[:customer], starts_at: ten, ends_at: ten + 1.hour, status:)
  end

  it "10:00-11:00 en la empresa A y reserva a las 10:30 en la empresa B: PersonUnavailable", :aggregate_failures do
    block_person_in_a

    expect { book_in(b, ten + 30.minutes) }.to raise_error(Appointments::PersonUnavailable)
    expect(Appointments::Appointment.where(company_id: company_b.id)).to be_empty
    expect(Events::OutboxEvent.where(name: "appointments.appointment_booked.v1")).to be_empty
  end

  it "el bloque contiguo (a las 11:00) sí se reserva", :aggregate_failures do
    block_person_in_a

    appointment = book_in(b, ten + 1.hour)

    expect(appointment).to be_persisted
    expect(appointment.company_id).to eq(company_b.id)
  end

  it "los buffers cuentan: una reserva cuyo bloque llega a la cita de la otra empresa se rechaza" do
    b[:service].update!(buffer_before_minutes: 20)
    block_person_in_a

    expect { book_in(b, ten + 75.minutes) }.to raise_error(Appointments::PersonUnavailable)
  end

  it "una ficha sin user_id no hace la comprobación entre empresas" do
    solo = setup_company(create_in(organization, :company))
    create(:appointment, professional: a[:professional], branch: a[:branch], customer: a[:customer], starts_at: ten, ends_at: ten + 1.hour)

    expect(book_in(solo, ten + 30.minutes)).to be_persisted
  end

  it "una cita cancelada de la ficha de A no bloquea a la ficha de B" do
    block_person_in_a(status: "cancelled")

    expect(book_in(b, ten + 30.minutes)).to be_persisted
  end

  it "la persona ocupada en A también lo está para su propia ficha de A (el motor lo ve: SlotUnavailable, no PersonUnavailable)" do
    block_person_in_a

    expect { book_in(a, ten + 30.minutes) }.to raise_error(Appointments::SlotUnavailable)
  end
end

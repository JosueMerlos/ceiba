require "rails_helper"

RSpec.describe Appointments::Cancel do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:, duration_minutes: 30) }
  let(:professional) { create_in(organization, :professional, company:) }

  def customer = @customer ||= create_in(organization, :customer, company:)
  def actor = @actor ||= Struct.new(:actor_type, :id).new("user", SecureRandom.uuid)
  def ten = Time.utc(2026, 11, 16, 16)
  def now = Time.utc(2026, 11, 1)

  around { |example| with_tenant(organization) { example.run } }

  before do
    Modules::Enable.call(company:, key: "appointments")
    create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create(:professional_branch_assignment, professional:, branch:)
    create(:professional_service, professional:, service:)
    create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  def book
    Appointments::Book.call(company:, branch:, customer_id: customer.id, services: [ service ],
                            professional: Appointments::Availability::ProfessionalChoice.of(professional), starts_at: ten, source: "panel", actor:, now:)
  end

  def appointment = @appointment ||= book

  def cancel(reason: "customer_request", cancelled_by: "staff", on: appointment)
    described_class.call(appointment: on, reason:, cancelled_by:, actor:, now:)
  end

  def errors_of(**options)
    cancel(**options)
    raise "expected InvalidCancellation"
  rescue Appointments::InvalidCancellation => error
    error.errors
  end

  it "cancela guardando quién y el motivo" do
    expect(cancel(reason: "professional_unavailable").reload)
      .to have_attributes(status: "cancelled", cancelled_by: "staff", cancellation_reason: "professional_unavailable")
  end

  it "rechaza un motivo fuera de la lista o vacío sin tocar la cita", :aggregate_failures do
    expect(errors_of(reason: "me caía mal")).to eq([ { field: :reason, code: :invalid } ])
    expect(errors_of(reason: nil)).to eq([ { field: :reason, code: :blank } ])
    expect(appointment.reload).to have_attributes(status: "scheduled", lock_version: 0)
  end

  it "rechaza quién canceló fuera de la lista como error del llamador" do
    expect { cancel(cancelled_by: "robot") }.to raise_error(ArgumentError, /cancelled_by/)
  end

  it "libera el hueco: se puede volver a reservar la misma hora" do
    cancel

    expect(book).to have_attributes(status: "scheduled", starts_at: ten)
  end

  it "cancelar dos veces es InvalidTransition" do
    cancel

    expect { cancel }.to raise_error(Appointments::InvalidTransition)
  end
end

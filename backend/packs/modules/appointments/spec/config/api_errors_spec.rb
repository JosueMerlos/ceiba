require "rails_helper"

RSpec.describe "Errores de la reserva en el registro de la API" do
  around { |example| I18n.with_locale(:"es-NI") { example.run } }

  def resolved(error) = Api::ErrorRegistry.resolve(error)

  it "SlotUnavailable es 409 appointments.slot_unavailable" do
    expect(resolved(Appointments::SlotUnavailable.new)).to have_attributes(status: 409, code: "appointments.slot_unavailable")
  end

  it "PersonUnavailable es 409 appointments.person_unavailable" do
    expect(resolved(Appointments::PersonUnavailable.new)).to have_attributes(status: 409, code: "appointments.person_unavailable")
  end

  it "InvalidBooking es 422 appointments.booking_invalid y lista cada error con su mensaje traducido", :aggregate_failures do
    entry = resolved(Appointments::InvalidBooking.new([ { field: :customer_id, code: :invalid }, { field: :professional_id, code: :any_not_allowed } ]))

    expect(entry).to have_attributes(status: 422, code: "appointments.booking_invalid")
    expect(entry.errors).to eq([
      { field: "customer_id", code: "invalid", message: I18n.t("appointments.booking.errors.customer_id.invalid", raise: true) },
      { field: "professional_id", code: "any_not_allowed", message: I18n.t("appointments.booking.errors.professional_id.any_not_allowed", raise: true) }
    ])
  end

  it "cada código tiene un título traducido (no el genérico de HTTP)", :aggregate_failures do
    %w[slot_unavailable person_unavailable booking_invalid].each do |key|
      expect(I18n.t("api.errors.appointments.#{key}", raise: true)).to be_present
    end
  end

  it "todos los mensajes de campo de la reserva existen", :aggregate_failures do
    {
      customer_id: %i[invalid], source: %i[invalid], notes: %i[too_long], starts_at: %i[blank], professional_id: %i[any_not_allowed]
    }.each do |field, codes|
      codes.each { |code| expect(I18n.t("appointments.booking.errors.#{field}.#{code}", raise: true)).to be_present }
    end
  end

  it "el YAML conserva las claves que ya existían", :aggregate_failures do
    expect(I18n.t("api.errors.appointments.availability_invalid", raise: true)).to eq("No se puede calcular la disponibilidad con esos datos")
    expect(I18n.t("appointments.availability.errors.branch_id.inactive", raise: true)).to eq("la sucursal está inactiva")
    expect(I18n.t("activerecord.errors.models.appointments/resource.attributes.base.archived", raise: true)).to eq("el recurso está archivado y no admite cambios")
  end
end

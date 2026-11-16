require "rails_helper"

RSpec.describe Appointments::AppointmentService do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:service) { create_in(organization, :service, company:) }

  around { |example| with_tenant(organization) { example.run } }

  def build_line(appointment) = appointment.services_snapshot.build(company_id: company.id, service_id: service.id, position: 0, duration_minutes: 30,
                                                                    buffer_before_minutes: 0, buffer_after_minutes: 0, price_minor: 20_000, currency: "NIO")

  it "se crea con la cita y queda como línea de solo lectura", :aggregate_failures do
    line = build_line(create(:appointment, professional: create(:professional, company:)))

    expect(line.save!).to be(true)
    expect { line.update!(price_minor: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { line.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end

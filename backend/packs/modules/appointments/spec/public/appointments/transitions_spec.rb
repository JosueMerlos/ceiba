require "rails_helper"

RSpec.describe Appointments::Transitions do
  # Read off the state diagram of the appointments domain by hand, independently of the table under test.
  def diagram
    { "scheduled" => %w[confirmed checked_in cancelled rescheduled no_show], "confirmed" => %w[checked_in cancelled rescheduled no_show],
      "checked_in" => %w[completed] }
  end

  def statuses = %w[scheduled confirmed checked_in completed cancelled rescheduled no_show]

  it "acepta exactamente las transiciones del diagrama en las 49 combinaciones de origen y destino", :aggregate_failures do
    statuses.product(statuses).each do |from, to|
      expect(described_class.allowed?(from:, to:)).to eq(diagram.fetch(from, []).include?(to)), "#{from} -> #{to}"
    end
  end

  it "deja sin salida los estados finales", :aggregate_failures do
    %w[completed cancelled rescheduled no_show].each do |final|
      expect(statuses.none? { described_class.allowed?(from: final, to: it) }).to be(true), final
    end
  end

  it "da a cada acción su estado destino y sus orígenes", :aggregate_failures do
    expected = {
      confirm: [ "confirmed", %w[scheduled] ], check_in: [ "checked_in", %w[scheduled confirmed] ], complete: [ "completed", %w[checked_in] ],
      no_show: [ "no_show", %w[scheduled confirmed] ], cancel: [ "cancelled", %w[scheduled confirmed] ],
      reschedule: [ "rescheduled", %w[scheduled confirmed] ]
    }

    expect(described_class.actions).to match_array(expected.keys)
    expected.each do |action, (to, from)|
      expect(described_class.fetch(action)).to have_attributes(to:, from: match_array(from))
    end
  end

  it "solo confirmar, hacer check-in, completar y marcar no-show se permiten sobre las citas propias", :aggregate_failures do
    expect(described_class.actions.select { described_class.fetch(it).own? }).to contain_exactly(:confirm, :check_in, :complete, :no_show)
    expect(described_class.fetch(:cancel).own?).to be(false)
    expect(described_class.fetch(:reschedule).own?).to be(false)
  end

  it "solo no_show exige que la cita haya empezado" do
    expect(described_class.actions.select { described_class.fetch(it).not_before_start? }).to eq([ :no_show ])
  end

  it "solo la cancelación admite columnas además del estado" do
    expect(described_class.actions.to_h { [ it, described_class.fetch(it).attributes ] })
      .to include(cancel: %i[cancelled_by cancellation_reason], confirm: [], reschedule: [])
  end

  it "cada acción tiene su ruta POST en la sucursal, y no hay rutas de acciones que la tabla no conozca" do
    routed = Rails.application.routes.routes.filter_map do |route|
      route.path.spec.to_s[%r{/branches/:branch_id/appointments/:appointment_id/(\w+)}, 1] if route.verb == "POST"
    end

    expect(routed.map(&:to_sym)).to match_array(described_class.actions)
  end

  it "una acción desconocida es un error del llamador, también como string", :aggregate_failures do
    expect { described_class.fetch(:archive) }.to raise_error(ArgumentError, /archive/)
    expect(described_class.fetch("confirm").to).to eq("confirmed")
  end
end

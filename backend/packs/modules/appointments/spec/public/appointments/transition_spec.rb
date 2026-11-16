require "rails_helper"

RSpec.describe Appointments::Transition do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  around { |example| with_tenant(organization) { example.run } }

  def starts_at = Time.utc(2026, 11, 16, 16)
  def actor = @actor ||= Struct.new(:actor_type, :id).new("user", SecureRandom.uuid)
  def appointment_in(status) = create(:appointment, professional:, branch:, status:, starts_at:)

  def transition(appointment, action, now: starts_at + 1.hour, **options, &block)
    described_class.call(appointment:, action:, actor:, now:, **options, &block)
  end

  def events_named(name) = Events::OutboxEvent.where(name:)
  def outbox_count = Events::OutboxEvent.where("name LIKE 'appointments.%'").count
  def audit_count = Audit::Event.where("action LIKE 'appointments.appointment.%'").count

  def rejection(appointment, action, **options)
    transition(appointment, action, **options)
    raise "expected InvalidTransition"
  rescue Appointments::InvalidTransition => error
    error
  end

  describe "transiciones válidas" do
    [
      [ :confirm, "scheduled", "confirmed", "appointments.appointment_confirmed.v1" ],
      [ :check_in, "scheduled", "checked_in", "appointments.appointment_checked_in.v1" ],
      [ :check_in, "confirmed", "checked_in", "appointments.appointment_checked_in.v1" ],
      [ :complete, "checked_in", "completed", "appointments.appointment_completed.v1" ],
      [ :no_show, "scheduled", "no_show", "appointments.appointment_no_show.v1" ],
      [ :no_show, "confirmed", "no_show", "appointments.appointment_no_show.v1" ]
    ].each do |action, from, to, event|
      it "#{action} desde #{from}: pasa a #{to}, sube la versión, publica #{event} y audita el antes y el después", :aggregate_failures do
        appointment = appointment_in(from)
        now = starts_at + 1.hour

        result = transition(appointment, action, now:)

        expect(result.reload).to have_attributes(status: to, lock_version: 1, updated_at: now)
        payload = events_named(event).sole.payload
        expect(payload.except("starts_at", "ends_at")).to eq(
          "appointment_id" => appointment.id, "branch_id" => branch.id, "professional_id" => professional.id,
          "customer_id" => appointment.customer_id, "from_status" => from
        )
        expect(Time.iso8601(payload["starts_at"])).to eq(starts_at)
        audit = Audit::Event.where(action: "appointments.appointment.#{to}").sole
        expect(audit).to have_attributes(auditable_id: appointment.id, actor_type: "user", actor_id: actor.id,
                                         before: { "status" => from }, after: { "status" => to })
        expect(outbox_count).to eq(1)
      end
    end

    it "cancelar guarda quién y por qué en la misma sentencia y los publica y audita", :aggregate_failures do
      appointment = appointment_in("confirmed")

      transition(appointment, :cancel, attributes: { cancelled_by: "customer", cancellation_reason: "customer_request" })

      expect(appointment.reload).to have_attributes(status: "cancelled", cancelled_by: "customer", cancellation_reason: "customer_request")
      expect(events_named("appointments.appointment_cancelled.v1").sole.payload)
        .to include("from_status" => "confirmed", "cancelled_by" => "customer", "cancellation_reason" => "customer_request")
      # The global parameter filter hides any *reason key in the audit trail; the code stays on the row, which no longer changes.
      expect(Audit::Event.where(action: "appointments.appointment.cancelled").sole.after)
        .to eq("status" => "cancelled", "cancelled_by" => "customer", "cancellation_reason" => "[FILTERED]")
    end

    it "parte del estado de la fila bloqueada, no del objeto que recibe" do
      appointment = appointment_in("scheduled")
      Appointments::Appointment.where(id: appointment.id).update_all(status: "confirmed")

      transition(appointment, :check_in)

      expect(events_named("appointments.appointment_checked_in.v1").sole.payload["from_status"]).to eq("confirmed")
    end
  end

  describe "transiciones inválidas" do
    it "cancelar una cita completada es InvalidTransition y no deja cambios, evento ni auditoría", :aggregate_failures do
      appointment = appointment_in("completed")

      error = rejection(appointment, :cancel, attributes: { cancelled_by: "staff", cancellation_reason: "other" })

      expect(error.errors).to eq([ { field: :status, code: :not_allowed } ])
      expect(appointment.reload).to have_attributes(status: "completed", lock_version: 0, cancelled_by: nil)
      expect([ outbox_count, audit_count ]).to eq([ 0, 0 ])
    end

    it "rechaza repetir una transición ya hecha (confirmar una confirmada)" do
      expect(rejection(appointment_in("confirmed"), :confirm).errors).to eq([ { field: :status, code: :not_allowed } ])
    end

    it "rechaza completar sin check-in" do
      expect(rejection(appointment_in("confirmed"), :complete).errors).to eq([ { field: :status, code: :not_allowed } ])
    end

    it "rechaza una cita que otra petición ya cambió aunque el objeto en memoria siga viejo", :aggregate_failures do
      appointment = appointment_in("scheduled")
      Appointments::Appointment.where(id: appointment.id).update_all(status: "cancelled", cancelled_by: "staff", cancellation_reason: "other")

      expect(rejection(appointment, :confirm).errors).to eq([ { field: :status, code: :not_allowed } ])
      expect(appointment.reload.status).to eq("cancelled")
    end
  end

  describe "precondición temporal" do
    it "no_show antes del inicio es too_early y no cambia nada", :aggregate_failures do
      appointment = appointment_in("scheduled")

      error = rejection(appointment, :no_show, now: starts_at - 1.minute)

      expect(error.errors).to eq([ { field: :status, code: :too_early } ])
      expect(appointment.reload.status).to eq("scheduled")
    end

    it "no_show justo a la hora de inicio se permite" do
      expect(transition(appointment_in("scheduled"), :no_show, now: starts_at).status).to eq("no_show")
    end

    it "las demás acciones no exigen que la cita haya empezado" do
      expect(transition(appointment_in("scheduled"), :check_in, now: starts_at - 2.hours).status).to eq("checked_in")
    end
  end

  describe "atributos" do
    it "rechaza columnas que la acción no admite, sin tocar la fila", :aggregate_failures do
      appointment = appointment_in("scheduled")

      expect { transition(appointment, :confirm, attributes: { notes: "x" }) }.to raise_error(ArgumentError, /notes/)
      expect { transition(appointment, :cancel, attributes: { status: "completed", cancelled_by: "staff", cancellation_reason: "other" }) }
        .to raise_error(ArgumentError, /status/)
      expect(appointment.reload.status).to eq("scheduled")
    end
  end

  describe "bloque de seguimiento" do
    it "corre después del UPDATE y dentro del savepoint: si falla, la transición se revierte entera", :aggregate_failures do
      appointment = appointment_in("scheduled")
      seen = nil

      expect do
        transition(appointment, :confirm) do
          seen = Appointments::Appointment.find(appointment.id).status
          raise ArgumentError, "boom"
        end
      end.to raise_error(ArgumentError, "boom")

      expect(seen).to eq("confirmed")
      expect(appointment.reload).to have_attributes(status: "scheduled", lock_version: 0)
      expect([ outbox_count, audit_count ]).to eq([ 0, 0 ])
    end
  end

  describe "SQL" do
    it "bloquea la fila con FOR UPDATE y condiciona el UPDATE a los estados de origen", :aggregate_failures do
      appointment = appointment_in("confirmed")
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { transition(appointment, :check_in) }

      expect(statements).to include(a_string_matching(/SELECT .*"appointments".* FOR UPDATE/))
      expect(statements).to include(a_string_matching(/UPDATE "appointments" SET .* WHERE .*"appointments"\."status" IN \(/))
    end
  end

  describe "aislamiento" do
    it "no encuentra una cita de otra organización dentro del contexto propio" do
      stranger = create(:organization)
      foreign = create_in(stranger, :appointment, professional: create_in(stranger, :professional, company: create_in(stranger, :company)),
                                                 status: "scheduled", starts_at:)

      expect { transition(foreign, :confirm) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

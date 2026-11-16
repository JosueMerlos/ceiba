require "rails_helper"

# Behavior of the appointment lifecycle endpoints that the contract spec does not describe: who may do what on which appointment,
# what a refusal leaves behind and how the idempotency key and the version behave.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Ciclo de vida de la cita: peticiones" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let!(:signed_in) { sign_in(receptionist) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }

  # Monday 16 Nov 2026 in America/Managua (UTC-6): 10:00 local is 16:00Z; the clock is frozen on the 11th.
  def ten = Time.utc(2026, 11, 16, 16)

  before do
    travel_to Time.utc(2026, 11, 11, 12)
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
    make_bookable(professional)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  after { travel_back }

  def make_bookable(person)
    create_in(world.organization, :professional_branch_assignment, professional: person, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional: person, service:)
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional: person, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    person
  end

  # A user with the `professional` role at the branch and the professional record linked to it.
  def own_pair
    @own_pair ||= user_with_role("professional", world, branch: world.branch_a1).then do |user|
      [ user, make_bookable(create_in(world.organization, :professional, company: world.company_a, user_id: user.id)) ]
    end
  end

  def professional_user = own_pair.first
  def own_professional = own_pair.last

  def booked(at: ten, person: professional, notes: "Trae su tinte")
    with_tenant(world.organization) do
      Appointments::Book.call(company: world.company_a, branch: world.branch_a1, customer_id: customer.id, services: [ service ],
                              professional: Appointments::Availability::ProfessionalChoice.of(person), starts_at: at, source: "panel", notes:)
    end
  end

  def in_status(status, person: professional, at: ten)
    booked(person:, at:).tap do |appointment|
      columns = status == "cancelled" ? { cancelled_by: "staff", cancellation_reason: "other" } : {}
      with_tenant(world.organization) { Appointments::Appointment.where(id: appointment.id).update_all(status:, **columns) }
    end
  end

  def base(branch: world.branch_a1, company: world.company_a)
    "/api/v1/organizations/#{world.organization.id}/companies/#{company.id}/appointments/branches/#{branch.id}/appointments"
  end

  def act(appointment, action, params: {}, key: nil, session: signed_in, branch: world.branch_a1)
    headers = session.csrf_headers
    headers = headers.merge("Idempotency-Key" => key) if key
    post "#{base(branch:)}/#{appointment.id}/#{action}", params:, headers:, as: :json
  end

  def reload(appointment) = with_tenant(world.organization) { appointment.reload }
  def problem = response.parsed_body
  def outbox_count = with_tenant(world.organization) { Events::OutboxEvent.count }
  def audit_count = with_tenant(world.organization) { Audit::Event.count }
  def keys_stored = with_tenant(world.organization) { Idempotency::Key.count }

  describe "transiciones" do
    it "la recepción confirma: 200 con la cita confirmada y la versión nueva", :aggregate_failures do
      appointment = booked

      act(appointment, "confirm")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("id" => appointment.id, "status" => "confirmed", "lock_version" => 1)
    end

    it "la recepción hace check-in y completa" do
      appointment = booked
      act(appointment, "check_in")
      act(appointment, "complete")

      expect([ response.status, reload(appointment).status ]).to eq([ 200, "completed" ])
    end

    it "cancelar una cita completada es 409 appointments.invalid_transition y la cita no cambia", :aggregate_failures do
      appointment = in_status("completed")

      act(appointment, "cancel", params: { reason: "customer_request" })

      expect(response).to have_http_status(:conflict)
      expect(problem).to include("code" => "appointments.invalid_transition")
      expect(problem["errors"]).to eq([ { "field" => "status", "code" => "not_allowed", "message" => I18n.t("appointments.transition.errors.status.not_allowed") } ])
      expect(reload(appointment).status).to eq("completed")
    end

    it "no_show antes de la hora de inicio es 409 con too_early" do
      act(booked, "no_show")

      expect([ response.status, problem.dig("errors", 0, "code") ]).to eq([ 409, "too_early" ])
    end

    it "no_show después del inicio pasa" do
      appointment = booked
      travel_to ten + 10.minutes
      act(appointment, "no_show", session: sign_in(receptionist))

      expect(reload(appointment).status).to eq("no_show")
    end

    it "por la URL de otra sucursal de la empresa, sin membresía en ella, es 404 y la cita no cambia", :aggregate_failures do
      appointment = booked
      act(appointment, "confirm", branch: world.branch_a2)
      expect([ response.status, problem["code"] ]).to eq([ 404, "resource.not_found" ])
      expect(reload(appointment).status).to eq("scheduled")
    end

    it "una cita de otra sucursal pedida por la URL de la propia es 404" do
      foreign = create_in(world.organization, :appointment, professional:, branch: world.branch_a2, starts_at: ten + 1.day)

      act(foreign, "confirm")

      expect([ response.status, problem["code"] ]).to eq([ 404, "resource.not_found" ])
    end

    it "un id inexistente es 404" do
      post "#{base}/#{SecureRandom.uuid}/confirm", headers: signed_in.csrf_headers, as: :json

      expect([ response.status, problem["code"] ]).to eq([ 404, "resource.not_found" ])
    end

    it "org_owner, que solo ve conteos, recibe 403" do
      owner = user_with_role("org_owner", world)
      act(booked, "confirm", session: sign_in(owner))

      expect([ response.status, problem["code"] ]).to eq([ 403, "access.forbidden" ])
    end
  end

  describe "profesional (update_own)" do
    def professional_session = @professional_session ||= sign_in(professional_user)

    it "marca no_show de una cita de OTRO profesional: 403 y la cita no cambia", :aggregate_failures do
      appointment = booked
      travel_to ten + 10.minutes
      act(appointment, "no_show", session: professional_session)

      expect([ response.status, problem["code"] ]).to eq([ 403, "access.forbidden" ])
      expect(reload(appointment).status).to eq("scheduled")
    end

    it "marca no_show de la suya" do
      appointment = booked(person: own_professional)
      travel_to ten + 10.minutes
      act(appointment, "no_show", session: professional_session)

      expect([ response.status, reload(appointment).status ]).to eq([ 200, "no_show" ])
    end

    it "confirma, hace check-in y completa las suyas", :aggregate_failures do
      appointment = booked(person: own_professional)

      %w[confirm check_in complete].each do |action|
        act(appointment, action, session: professional_session)
        expect(response).to have_http_status(:ok), action
      end
    end

    it "no cancela ni reprograma ni siquiera las suyas", :aggregate_failures do
      appointment = booked(person: own_professional)

      act(appointment, "cancel", params: { reason: "other" }, session: professional_session)
      expect(response).to have_http_status(:forbidden)
      act(appointment, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" }, key: SecureRandom.uuid, session: professional_session)
      expect(response).to have_http_status(:forbidden)
      expect(reload(appointment).status).to eq("scheduled")
    end

    it "deja de actuar sobre sus citas de una sucursal cuando lo desasignan" do
      appointment = booked(person: own_professional)
      with_tenant(world.organization) do
        Appointments::WeeklySchedule.where(professional_id: own_professional.id).delete_all
        Appointments::ProfessionalBranchAssignment.where(professional_id: own_professional.id).delete_all
      end

      act(appointment, "confirm", session: professional_session)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "cancelar" do
    it "guarda el motivo y que canceló el personal", :aggregate_failures do
      appointment = booked

      act(appointment, "cancel", params: { reason: "professional_unavailable" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("status" => "cancelled", "cancelled_by" => "staff", "cancellation_reason" => "professional_unavailable")
    end

    it "sin motivo o con uno fuera de la lista es 422 appointments.cancellation_invalid", :aggregate_failures do
      appointment = booked

      act(appointment, "cancel")
      expect([ response.status, problem["code"], problem.dig("errors", 0, "code") ]).to eq([ 422, "appointments.cancellation_invalid", "blank" ])
      act(appointment, "cancel", params: { reason: "nada" })
      expect(problem.dig("errors", 0, "code")).to eq("invalid")
      expect(reload(appointment).status).to eq("scheduled")
    end
  end

  describe "reprogramar" do
    let(:key) { SecureRandom.uuid }

    def moved = with_tenant(world.organization) { Appointments::Appointment.where.not(rescheduled_from_id: nil).to_a }

    it "crea la cita nueva enlazada (201) y la original queda rescheduled", :aggregate_failures do
      appointment = booked

      act(appointment, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" }, key:)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("status" => "scheduled", "rescheduled_from_id" => appointment.id, "starts_at" => "2026-11-16T17:00:00.000Z",
                              "professional_id" => professional.id, "total_price_minor" => 20_000)
      expect(data).not_to have_key("notes")
      expect(reload(appointment).status).to eq("rescheduled")
    end

    it "con otro profesional asignado a la sucursal", :aggregate_failures do
      other = make_bookable(create_in(world.organization, :professional, company: world.company_a))

      act(booked, "reschedule", params: { starts_at: "2026-11-16T10:00:00-06:00", professional_id: other.id }, key:)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "professional_id")).to eq(other.id)
    end

    it "exige Idempotency-Key", :aggregate_failures do
      act(booked, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" })

      expect([ response.status, problem["code"] ]).to eq([ 400, "idempotency.key_required" ])
      expect(moved).to be_empty
    end

    it "la misma clave y el mismo cuerpo repiten la respuesta sin crear otra cita", :aggregate_failures do
      appointment = booked
      act(appointment, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" }, key:)
      first = response.parsed_body

      act(appointment, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" }, key:)

      expect(response.parsed_body).to eq(first)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(moved.size).to eq(1)
    end

    it "a un hueco ocupado: 409, la original sigue scheduled, nada nuevo y la clave no se consume", :aggregate_failures do
      appointment = booked
      booked(at: ten + 1.hour, notes: nil)
      before = [ outbox_count, audit_count ]

      act(appointment, "reschedule", params: { starts_at: "2026-11-16T11:00:00-06:00" }, key:)

      expect([ response.status, problem["code"] ]).to eq([ 409, "appointments.slot_unavailable" ])
      expect(reload(appointment)).to have_attributes(status: "scheduled", lock_version: 0)
      expect(moved).to be_empty
      expect([ outbox_count, audit_count ]).to eq(before)
      expect(keys_stored).to eq(0)
    end

    it "sin starts_at es 400 request.invalid" do
      act(booked, "reschedule", params: {}, key:)

      expect([ response.status, problem["code"] ]).to eq([ 400, "request.invalid" ])
    end
  end

  describe "detalle y notas" do
    def detail_path(appointment) = "#{base}/#{appointment.id}"

    it "el detalle incluye las notas para quien puede editar la cita" do
      get detail_path(booked)

      expect(response.parsed_body["data"]).to include("notes" => "Trae su tinte", "lock_version" => 0)
    end

    it "un profesional ve las notas de las suyas y no el detalle de las ajenas", :aggregate_failures do
      session = sign_in(professional_user)
      get detail_path(booked(person: own_professional)), headers: session.csrf_headers
      expect(response.parsed_body.dig("data", "notes")).to eq("Trae su tinte")

      get detail_path(booked(at: ten + 1.hour)), headers: session.csrf_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "edita las notas con la versión vigente y las audita filtradas", :aggregate_failures do
      appointment = booked

      patch detail_path(appointment), params: { notes: "Alérgica al látex", lock_version: 0 }, headers: signed_in.csrf_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("notes" => "Alérgica al látex", "lock_version" => 1)
      audit = with_tenant(world.organization) { Audit::Event.where(action: "appointments.appointment.notes_updated").sole }
      expect(audit).to have_attributes(auditable_id: appointment.id, actor_id: receptionist.id, after: { "notes" => "[FILTERED]" })
    end

    it "con una versión vieja es 409 resource.stale y no cambia nada", :aggregate_failures do
      appointment = booked
      act(appointment, "confirm")

      patch detail_path(appointment), params: { notes: "otra cosa", lock_version: 0 }, headers: signed_in.csrf_headers, as: :json

      expect([ response.status, problem["code"] ]).to eq([ 409, "resource.stale" ])
      expect(reload(appointment).notes).to eq("Trae su tinte")
    end

    it "sin lock_version es 400 y con notas demasiado largas es 422", :aggregate_failures do
      appointment = booked

      patch detail_path(appointment), params: { notes: "x" }, headers: signed_in.csrf_headers, as: :json
      expect([ response.status, problem["code"] ]).to eq([ 400, "request.invalid" ])
      patch detail_path(appointment), params: { notes: "x" * 501, lock_version: 0 }, headers: signed_in.csrf_headers, as: :json
      expect([ response.status, problem["code"] ]).to eq([ 422, "validation.failed" ])
    end

    it "notas nulas las borran" do
      appointment = booked

      patch detail_path(appointment), params: { notes: nil, lock_version: 0 }, headers: signed_in.csrf_headers, as: :json

      expect(reload(appointment).notes).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers

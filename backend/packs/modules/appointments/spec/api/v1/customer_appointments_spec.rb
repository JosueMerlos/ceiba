require "swagger_helper"

# A customer's appointment history at the branch the staff acts from, for the customer profile.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: historial de citas de un cliente" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
  let!(:modules_enabled) { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }
  let(:customer_id) { customer.id }

  def visit(starts_at, status, service:, professional:)
    with_tenant(world.organization) do
      columns = status == "cancelled" ? { cancelled_by: "customer", cancellation_reason: "customer_request" } : {}
      create(:appointment, professional:, branch: world.branch_a1, customer:, starts_at:, status:, **columns).tap { create(:appointment_service, appointment: it, service:) }
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/customers/{customer_id}/appointments" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :customer_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Historial de citas de un cliente en la sucursal" do
      tags "Citas"
      description "De la más reciente a la más antigua, paginado por cursor. Solo las citas de la sucursal de la ruta. Exige " \
                  "`appointments.appointment.read` en la sucursal. Un cliente archivado conserva su historial."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      response "200", "las citas con su estado y los nombres de profesional y servicio" do
        schema type: :object, required: %w[data page], additionalProperties: false, properties: {
          data: { type: :array, items: { "$ref" => "#/components/schemas/CustomerAppointment" } },
          page: { "$ref" => "#/components/schemas/PageInfo" }
        }
        let!(:visits) do
          service = create_in(world.organization, :service, company: world.company_a, name: "Corte")
          professional = create_in(world.organization, :professional, company: world.company_a, display_name: "Marta")
          { completed: visit(Time.utc(2026, 11, 2, 15), "completed", service:, professional:), no_show: visit(Time.utc(2026, 11, 9, 15), "no_show", service:, professional:),
            cancelled: visit(Time.utc(2026, 11, 5, 15), "cancelled", service:, professional:) }
        end

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data.map { it.values_at("id", "status") }).to eq([ [ visits[:no_show].id, "no_show" ], [ visits[:cancelled].id, "cancelled" ], [ visits[:completed].id, "completed" ] ])
          expect(data.first.slice("starts_at", "professional", "services"))
            .to eq("starts_at" => "2026-11-09T15:00:00.000Z", "professional" => { "id" => visits[:no_show].professional_id, "display_name" => "Marta" },
                   "services" => [ { "service_id" => with_tenant(world.organization) { visits[:no_show].services_snapshot.first.service_id }, "name" => "Corte" } ])
        end
      end

      response "404", "un cliente de otra empresa no existe para esta ruta" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:customer_id) { create_in(world.organization, :customer, company: world.company_b).id }

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers

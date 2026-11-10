# Idempotency test endpoints. There are no real create endpoints yet, so the Idempotency::Idempotent concern is tested
# against a probe that CREATES A COMPANY (a real, countable resource). The routes exist only in the groups that ask for
# them (same pattern as ApiProbes). The probe inherits Api::BaseController, like any pack controller. In authenticated
# actions the context is opened by Access::Authorization from the route (/organizations/:organization_id/..., requires a
# membership); PUBLIC actions (anonymous principal) open their own, as the public booking will when resolving the
# organization by slug.
module IdempotencyProbes
  def self.define_controller!
    return if const_defined?(:ProbesController, false)

    const_set(:ProbesController, Class.new(Api::BaseController) do
      include Idempotency::Idempotent

      skip_authentication! only: %i[public_create slow_create no_context]
      skip_authorization! reason: "sondas de test de la idempotencia: crean empresas de prueba, no autorizan un recurso", only: %i[
        create required_create soft_fail public_create slow_create no_context audit_in_get idempotent_get
      ]
      # Declared BEFORE `idempotent`: the context must be open when the key filter runs.
      around_action :in_public_organization, only: %i[public_create slow_create]

      idempotent :create, :public_create, :slow_create, :soft_fail
      idempotent :required_create, required: true
      idempotent :no_context, :idempotent_get

      def create = create_company
      def public_create = create_company
      def required_create = create_company
      def no_context = head(:created)

      # Reads: run in a READ-ONLY transaction (Access::RouteContextResolver). Writing in them must fail.
      def audit_in_get
        Audit.record(action: "probe.read", subject: Current.context.organization)
        head :ok
      end

      def idempotent_get = head(:ok)

      # Answers 422 WITHOUT raising an exception (the "render 4xx" path).
      def soft_fail = render(json: { error: "rechazada" }, status: :unprocessable_content)

      def slow_create
        sleep params[:delay].to_f
        create_company
      end

      private

      def in_public_organization(&)
        Tenancy.with_context(organization: Tenancy::Organization.find(params[:organization_id]), principal: Current.principal, &)
      end

      def create_company
        company = Tenancy::AddCompany.call(
          organization: Current.context.organization, name: params[:name], slug: "sonda-#{SecureRandom.hex(4)}", business_type: "salon", currency: "NIO"
        )
        response.set_header("Location", "/api/v1/probes/companies/#{company.id}")
        render json: { data: { id: company.id, name: company.name } }, status: :created
      end
    end)
  end

  module Helpers
    def idempotency_routes
      IdempotencyProbes.define_controller!
      Rails.application.reload_routes_unless_loaded
      Rails.application.routes.disable_clear_and_finalize = true
      Rails.application.routes.draw do
        scope path: "api/v1/idempotency_probes", controller: "idempotency_probes/probes" do
          post "organizations/:organization_id/companies", action: :create
          post "organizations/:organization_id/companies_alias", action: :create
          post "organizations/:organization_id/slow_companies", action: :slow_create
          post "organizations/:organization_id/required_companies", action: :required_create
          post "organizations/:organization_id/public_companies", action: :public_create
          post "organizations/:organization_id/soft_fails", action: :soft_fail
          post "no_context", action: :no_context
          get "organizations/:organization_id/audit_in_get", action: :audit_in_get
          get "organizations/:organization_id/idempotent_get", action: :idempotent_get
        end
      end
    ensure
      Rails.application.routes.disable_clear_and_finalize = false
    end
  end
end

RSpec.shared_context "con endpoints de prueba de idempotencia" do
  before(:context) { extend IdempotencyProbes::Helpers; idempotency_routes } # rubocop:disable RSpec/BeforeAfterAll -- drawing routes is expensive and global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end

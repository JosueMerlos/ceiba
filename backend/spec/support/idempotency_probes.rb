# Endpoints de prueba de la idempotencia (M0.11). Aún no hay endpoints de creación reales, así que el concern
# Idempotency::Idempotent se prueba sobre una sonda que CREA UNA EMPRESA (un recurso real, contable). Las rutas existen solo
# en los grupos que las piden (mismo patrón que ApiProbes). La sonda hereda de Api::BaseController, como cualquier
# controlador de un pack, y abre el contexto de tenancy desde la ruta (lo que hará el control de acceso en M0.08).
module IdempotencyProbes
  def self.define_controller!
    return if const_defined?(:ProbesController, false)

    const_set(:ProbesController, Class.new(Api::BaseController) do
      include Idempotency::Idempotent

      skip_authentication! only: %i[public_create no_context]
      around_action :in_organization, except: :no_context

      idempotent :create, :public_create, :slow_create
      idempotent :required_create, required: true
      idempotent :no_context

      def create = create_company
      def public_create = create_company
      def required_create = create_company
      def no_context = head(:created)

      def slow_create
        sleep params[:delay].to_f
        create_company
      end

      private

      def in_organization(&)
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
          post "organizations/:organization_id/slow_companies", action: :slow_create
          post "organizations/:organization_id/required_companies", action: :required_create
          post "organizations/:organization_id/public_companies", action: :public_create
          post "no_context", action: :no_context
        end
      end
    ensure
      Rails.application.routes.disable_clear_and_finalize = false
    end
  end
end

RSpec.shared_context "con endpoints de prueba de idempotencia" do
  before(:context) { extend IdempotencyProbes::Helpers; idempotency_routes } # rubocop:disable RSpec/BeforeAfterAll -- dibujar rutas es caro y global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end

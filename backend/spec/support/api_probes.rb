# Endpoints de prueba para los specs del contrato API (M0.06). Viven solo en la suite: se dibujan en el router para el
# grupo que los pide y se descartan al terminar, de modo que ningún endpoint de prueba existe en la aplicación real.
#
# Hereda de Api::BaseController (el controlador base de la API), igual que cualquier controlador de un pack.
module ApiProbes
  UNKNOWN_ID = "0198f0a0-0000-7000-8000-000000000000".freeze

  # Se define bajo demanda (no al cargar el archivo) para no depender de Api::BaseController en cada spec de la suite.
  def self.define_controller!
    return if const_defined?(:ProbesController, false)

    const_set(:ProbesController, Class.new(Api::BaseController) do
      def show = render(json: { data: { ok: true } })
      def invalid_record = Tenancy::Organization.new.validate!
      def stale_record = raise(ActiveRecord::StaleObjectError.new(Tenancy::Organization.new, "update"))
      def duplicate = raise(ActiveRecord::RecordNotUnique, "PG::UniqueViolation: duplicate key value violates unique constraint secret_index")
      def missing_record = Tenancy::Organization.find(UNKNOWN_ID)
      def missing_param = params.expect(:required_thing)
      def create = render(json: { received: params[:name] }, status: :created)
      def slug_taken = raise(Tenancy::ProvisioningFailed.new(:slug_taken, "el slug ya está en uso", details: { company: { slug: [ "ya está en uso" ] } }))
      def slug_reserved = raise(Tenancy::ProvisioningFailed.new(:slug_reserved, "slug reservado", details: { company: { slug: [ "está reservado" ] } }))
      def inconsistent_context = raise(Tenancy::InconsistentContext, "la sucursal no es de la empresa company-secreta")
      def tenant_mismatch = raise(Tenancy::TenantMismatch, "organization_id ajeno")
      def boom = raise("kaboom: /app/backend/secret_path.rb contraseña=hunter2")
      def unregistered = raise(ProbeDomainError, "detalle interno que no debe salir")
    end)
  end

  class ProbeDomainError < StandardError; end

  module Helpers
    def probes_routes
      ApiProbes.define_controller!
      Rails.application.reload_routes_unless_loaded # las rutas reales primero: draw sin esto las dejaría sin cargar
      Rails.application.routes.disable_clear_and_finalize = true
      Rails.application.routes.draw do
        scope path: "api/v1/probes", controller: "api_probes/probes" do
          get "ok", action: :show
          get "invalid_record"
          get "stale_record"
          get "duplicate"
          get "missing_record"
          get "missing_param"
          get "slug_taken"
          get "slug_reserved"
          get "inconsistent_context"
          get "tenant_mismatch"
          get "boom"
          get "unregistered"
          post "create"
        end
      end
    ensure
      Rails.application.routes.disable_clear_and_finalize = false
    end
  end
end

RSpec.shared_context "con endpoints de prueba de la API" do
  before(:context) { extend ApiProbes::Helpers; probes_routes } # rubocop:disable RSpec/BeforeAfterAll -- dibujar rutas es caro y global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end

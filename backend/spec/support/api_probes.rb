# Endpoints de prueba para los specs del contrato API (M0.06). Viven solo en la suite: se dibujan en el router para el
# grupo que los pide y se descartan al terminar, de modo que ningún endpoint de prueba existe en la aplicación real.
#
# Hereda de Api::BaseController (el controlador base de la API), igual que cualquier controlador de un pack.
module ApiProbes
  UNKNOWN_ID = "0198f0a0-0000-7000-8000-000000000000".freeze

  # Se define bajo demanda (no al cargar el archivo) para no depender de Api::BaseController en cada spec de la suite.
  def self.define_controller!
    define_serializer!
    return if const_defined?(:ProbesController, false)

    const_set(:ProbesController, Class.new(Api::BaseController) do
      # Las sondas prueban los rescates de la API, no la autenticación: son públicas salvo `guarded`, que representa
      # "una ruta nueva que nadie marcó como pública" y debe responder 401 (spec/requests/api/authentication_spec.rb).
      skip_authentication! except: :guarded

      def show = render(json: { data: { ok: true } })
      def guarded = render(json: { data: { ok: true } })
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
      def organizations = render_page(Tenancy::Organization.all, serializer: ApiProbes::OrganizationSerializer)
      def unknown_format = raise(ActionController::UnknownFormat)
      def not_implemented = raise(ActionController::NotImplemented)
      def client_error_unregistered = raise(ActionController::InvalidAuthenticityToken)
      def unregistered = raise(ProbeDomainError, "detalle interno que no debe salir")
    end)
  end

  # Serializer mínimo de la sonda de paginación (un serializer por representación: ver Api::Serializer).
  def self.define_serializer!
    return if const_defined?(:OrganizationSerializer, false)

    const_set(:OrganizationSerializer, Class.new do
      include Alba::Resource

      attributes :id, :name
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
          get "guarded"
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
          get "unknown_format"
          get "not_implemented"
          get "client_error_unregistered"
          get "organizations"
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

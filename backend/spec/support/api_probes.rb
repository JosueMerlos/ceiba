# Test endpoints for the API contract specs. They live only in the suite: they are drawn on the router for the group
# that asks for them and dropped afterwards, so no test endpoint exists in the real application.
#
# Inherits Api::BaseController (the API base controller), like any pack controller.
module ApiProbes
  UNKNOWN_ID = "0198f0a0-0000-7000-8000-000000000000".freeze

  # Defined on demand (not when the file loads) so no spec in the suite depends on Api::BaseController.
  def self.define_controller!
    define_serializer!
    return if const_defined?(:ProbesController, false)

    const_set(:ProbesController, Class.new(Api::BaseController) do
      # The probes test the API rescues, not authentication: they are public except `guarded`, which stands for "a new
      # route nobody marked public" and must answer 401 (see authentication_spec).
      skip_authentication! except: :guarded
      skip_authorization! reason: "sondas de test del contrato de errores: no devuelven recursos de ninguna organización", except: :guarded

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

  # Minimal serializer for the pagination probe (one serializer per representation: see Api::Serializer).
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
      Rails.application.reload_routes_unless_loaded # real routes first: draw without this would leave them unloaded
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
  before(:context) { extend ApiProbes::Helpers; probes_routes } # rubocop:disable RSpec/BeforeAfterAll -- drawing routes is expensive and global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end

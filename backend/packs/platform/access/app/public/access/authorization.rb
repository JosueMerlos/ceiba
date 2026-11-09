module Access
  # Autorización de la API (ADR-0007). Lo incluye Api::BaseController, así que TODO controlador de la API queda con:
  #
  #   1. el principal de acceso (Access::Principal::User) construido desde la sesión;
  #   2. el contexto resuelto desde la ruta y validado contra sus memberships (Access::RouteContextResolver) cuando la ruta trae
  #      organization_id (o el parámetro equivalente, ver `route_context`);
  #   3. `verify_authorized` tras cada acción y `verify_policy_scoped` tras cada `index`: una acción que no autoriza FALLA
  #      (500 con el detalle en el log), y como corre DENTRO del contexto, lo que la acción haya escrito se revierte.
  #
  # Para una acción que de verdad no autoriza (login, logout, sesión) se declara `skip_authorization!(reason:)`; la lista queda
  # en `authorization_skips` y un spec la compara con una allowlist.
  #
  # Rutas cuyo recurso ES la organización, la empresa o la sucursal usan su `:id` como identificador:
  #
  #   route_context organization: :id        # GET /organizations/:id
  #   route_context company: :id             # GET /organizations/:organization_id/companies/:id
  module Authorization
    extend ActiveSupport::Concern

    DEFAULT_ROUTE_PARAMS = { organization: :organization_id, company: :company_id, branch: :branch_id }.freeze

    included do
      include Pundit::Authorization

      class_attribute :authorization_skips, instance_writer: false, default: []
      class_attribute :route_context_params, instance_writer: false, default: DEFAULT_ROUTE_PARAMS

      before_action :establish_access_principal!
      around_action :within_route_context
      # Declarados DESPUÉS del around: sus after_action corren dentro del contexto (y de su transacción).
      after_action :verify_authorized
      after_action :verify_policy_scoped, only: :index

      # Definido en la clase (no en el módulo): Pundit::Authorization, incluido arriba, define su propio pundit_user
      # (current_user) y ganaría en la resolución de métodos.
      def pundit_user = Current.principal
      private :pundit_user
    end

    class_methods do
      def skip_authorization!(reason:, **options)
        raise ArgumentError, "skip_authorization! exige un motivo (reason:)" if reason.to_s.strip.empty?

        skip_after_action :verify_authorized, :verify_policy_scoped, raise: false, **options
        self.authorization_skips = authorization_skips + [ { reason:, **options } ]
      end

      def route_context(**params) = self.route_context_params = route_context_params.merge(params)
    end

    private

    # La sesión entrega la identidad (Identity::Principal::User); aquí se envuelve en el principal que sabe de permisos.
    def establish_access_principal!
      identity = Current.principal
      Current.principal = Principal::User.new(identity) if identity.is_a?(::Identity::Principal::User)
    end

    def within_route_context(&)
      principal = Current.principal
      # SOLO los parámetros de la RUTA: `params` mezcla query y cuerpo, y un cliente podría fijar el contexto con
      # `?organization_id=`. path_parameters viene únicamente del router.
      route = request.path_parameters
      organization_id = route[route_context_params.fetch(:organization)]
      return yield unless principal.is_a?(Principal::User) && organization_id.present?

      RouteContextResolver.call(
        principal:, organization_id:,
        company_id: route[route_context_params.fetch(:company)].presence,
        branch_id: route[route_context_params.fetch(:branch)].presence,
        &
      )
    end
  end
end

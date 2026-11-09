module Access
  # Autorización de la API (ADR-0007). Lo incluye Api::BaseController, así que TODO controlador de la API queda con:
  #
  #   1. el principal de acceso (Access::Principal::User) construido desde la sesión;
  #   2. el contexto resuelto desde la ruta y validado contra sus memberships (Access::RouteContextResolver) cuando la ruta trae
  #      organization_id (o el parámetro equivalente, ver `route_context`);
  #   3. `verify_authorized` tras CADA acción (una acción que no autoriza FALLA: 500 con el detalle en el log) y
  #      `verify_collection_scoped` tras cada acción que NO autorizó un registro concreto: autorizar una clase o una relación
  #      (listados, búsquedas, cualquier acción de colección, se llame como se llame) exige además `policy_scope`. Así no hay que
  #      declarar qué acciones son de colección ni depender de que se llamen `index`. Como corren DENTRO del contexto, lo que la
  #      acción haya escrito se revierte si fallan.
  #
  # Para una acción que de verdad no autoriza (login, logout, sesión) se declara `skip_authorization!(reason:, only:)`: `only:` o
  # `except:` son obligatorios (no existe el skip de todo el controlador), la lista queda en `authorization_skips` y
  # spec/requests/api/authorization_spec.rb la compara con una allowlist por ruta. El cop Ceiba/AuthorizationSkips prohíbe
  # cualquier otra forma de saltarse la verificación.
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
      after_action :verify_collection_scoped

      # Definido en la clase (no en el módulo): Pundit::Authorization, incluido arriba, define su propio pundit_user
      # (current_user) y ganaría en la resolución de métodos.
      def pundit_user = Current.principal
      private :pundit_user

      # Recuerda si la acción autorizó un REGISTRO concreto. Autorizar una clase o una relación (acciones de colección) obliga a
      # usar policy_scope; el resto de la firma es la de Pundit.
      def authorize(record, query = nil, policy_class: nil)
        authorized = super
        @member_authorized = true unless collection?(record)
        authorized
      end
      protected :authorize
    end

    class_methods do
      def skip_authorization!(reason:, **options)
        raise ArgumentError, "skip_authorization! exige un motivo (reason:)" if reason.to_s.strip.empty?
        raise ArgumentError, "skip_authorization! exige only: o except: (no se omite la autorización de todo un controlador)" unless options.key?(:only) || options.key?(:except)

        skip_after_action :verify_authorized, :verify_collection_scoped, raise: false, **options
        self.authorization_skips = authorization_skips + [ { reason:, **options } ]
      end

      def route_context(**params) = self.route_context_params = route_context_params.merge(params)
    end

    private

    def collection?(record)
      record = record.last if record.is_a?(Array)
      record.is_a?(Module) || record.is_a?(ActiveRecord::Relation)
    end

    def verify_collection_scoped
      # Si ni siquiera autorizó, verify_authorized (que corre después) da el error correcto.
      return if @member_authorized || pundit_policy_scoped? || !pundit_policy_authorized?

      raise Pundit::PolicyScopingNotPerformedError, self.class
    end

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
        read_only: request.get? || request.head?,
        &
      )
    end
  end
end

module Access
  # API authorization. Included by Api::BaseController, so EVERY API controller gets:
  #
  #   1. the access principal (Access::Principal::User) built from the session;
  #   2. the context resolved from the route and validated against its memberships (Access::RouteContextResolver) when the
  #      route carries organization_id (or the equivalent param, see `route_context`);
  #   3. `verify_authorized` after EVERY action (an action that does not authorize FAILS: 500 with details in the log) and
  #      `verify_collection_scoped` after every action that did NOT authorize a single record: authorizing a class or a
  #      relation (any collection action, whatever its name) also requires `policy_scope`. This avoids declaring which
  #      actions are collection ones or relying on them being called `index`. They run INSIDE the context, so whatever the
  #      action wrote is rolled back if they fail.
  #
  # An action that truly does not authorize (login, logout, session) declares `skip_authorization!(reason:, only:)`: `only:`
  # or `except:` is mandatory (no controller-wide skip), the list is kept in `authorization_skips` and
  # spec/requests/api/authorization_spec.rb compares it with a per-route allowlist. The Ceiba/AuthorizationSkips cop
  # forbids any other way to skip verification.
  #
  # Routes whose resource IS the organization, company or branch use its `:id` as the identifier:
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
      # Declared AFTER the around action so these after_actions run inside the context (and its transaction).
      after_action :verify_authorized
      after_action :verify_collection_scoped

      # Defined on the class (not the module): Pundit::Authorization, included above, defines its own pundit_user
      # (current_user) and would win method resolution.
      def pundit_user = Current.principal
      private :pundit_user

      # Remembers whether the action authorized a single RECORD. Authorizing a class or relation (collection actions)
      # requires policy_scope; the signature is otherwise Pundit's.
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
      # If nothing was authorized, verify_authorized (which runs later) raises the right error.
      return if @member_authorized || pundit_policy_scoped? || !pundit_policy_authorized?

      raise Pundit::PolicyScopingNotPerformedError, self.class
    end

    # The session provides the identity (Identity::Principal::User); it is wrapped in the principal that knows permissions.
    def establish_access_principal!
      identity = Current.principal
      Current.principal = Principal::User.new(identity) if identity.is_a?(::Identity::Principal::User)
    end

    def within_route_context(&)
      principal = Current.principal
      # ONLY route params: `params` mixes query and body, so a client could set the context with `?organization_id=`.
      # path_parameters comes solely from the router.
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

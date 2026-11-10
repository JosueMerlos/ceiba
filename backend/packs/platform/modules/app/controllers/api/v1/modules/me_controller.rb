module Api
  module V1
    module Modules
      # GET /api/v1/me: the authenticated user's context, active modules with resolved settings, permissions and navigation.
      # The SPA only reflects it: hiding something is not access control.
      #
      # The context is not in the route: it comes from params or the last-used signed cookie, and either way is validated
      # against memberships with Access.with_context, like a nested route.
      class MeController < ::Api::BaseController
        skip_authorization! reason: "devuelve el contexto y los permisos del propio principal; el contexto se valida con Access.with_context", only: :show

        def show
          user_id = Current.principal.id
          payload, selection = ::Modules::Me.call(principal: Current.principal, requested: requested_selection, remembered: ::Modules::ContextCookie.read(cookies, user_id:))
          ::Modules::ContextCookie.write(cookies, selection, user_id:) if selection
          render json: { data: payload }
        end

        private

        # `company_id` requires `organization_id` and `branch_id` requires `company_id`.
        def requested_selection
          organization_id = params[:organization_id].presence
          company_id = params[:company_id].presence
          branch_id = params[:branch_id].presence
          return if [ organization_id, company_id, branch_id ].none?

          params.expect(:organization_id) unless organization_id
          params.expect(:company_id) if branch_id && !company_id
          ::Modules::ContextCookie::Selection.new(organization_id: scalar(organization_id), company_id: scalar(company_id), branch_id: scalar(branch_id))
        end

        # A non-string param (?company_id[]=...) is not an id: treat it as a nonexistent id (404).
        def scalar(value) = value.nil? || value.is_a?(String) ? value : "0"
      end
    end
  end
end

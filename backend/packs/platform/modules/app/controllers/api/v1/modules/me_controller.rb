module Api
  module V1
    module Modules
      # GET /api/v1/me: el contexto del usuario autenticado, sus módulos activos con settings resueltos, sus permisos y la navegación
      # (docs/architecture/05-module-system.md). Es lo que la SPA REFLEJA: ocultar algo no es control de acceso.
      #
      # El contexto no va en la ruta: llega por parámetros (`organization_id`, `company_id`, `branch_id`) o es el último usado
      # (cookie firmada). En ambos casos se valida contra los memberships con Access.with_context, igual que una ruta anidada.
      class MeController < ::Api::BaseController
        skip_authorization! reason: "devuelve el contexto y los permisos del propio principal; el contexto se valida con Access.with_context", only: :show

        def show
          user_id = Current.principal.id
          payload, selection = ::Modules::Me.call(principal: Current.principal, requested: requested_selection, remembered: ::Modules::ContextCookie.read(cookies, user_id:))
          ::Modules::ContextCookie.write(cookies, selection, user_id:) if selection
          render json: { data: payload }
        end

        private

        # Los parámetros pedidos expresamente. `company_id` exige `organization_id` y `branch_id` exige `company_id`.
        def requested_selection
          organization_id = params[:organization_id].presence
          company_id = params[:company_id].presence
          branch_id = params[:branch_id].presence
          return if [ organization_id, company_id, branch_id ].none?

          params.expect(:organization_id) unless organization_id
          params.expect(:company_id) if branch_id && !company_id
          ::Modules::ContextCookie::Selection.new(organization_id: scalar(organization_id), company_id: scalar(company_id), branch_id: scalar(branch_id))
        end

        # Un parámetro que no es una cadena (?company_id[]=…) no es un id: se trata como un id inexistente (404).
        def scalar(value) = value.nil? || value.is_a?(String) ? value : "0"
      end
    end
  end
end

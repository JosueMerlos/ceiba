module Api
  module V1
    module Access
      # Empresas de la organización de la ruta, solo las que el principal puede leer. El contexto (organización y, en
      # `show`, la empresa) ya viene resuelto y validado por Access::Authorization.
      class CompaniesController < ::Api::BaseController
        route_context company: :id

        def index
          authorize ::Tenancy::Directory.companies, :index?, policy_class: ::Access::CompanyPolicy
          companies = policy_scope(::Tenancy::Directory.companies, policy_scope_class: ::Access::CompanyPolicy::Scope)
          render_page(companies, serializer: ::Tenancy::CompanySerializer)
        end

        def show
          company = Current.context.company
          authorize company, :show?, policy_class: ::Access::CompanyPolicy
          render json: { data: ::Tenancy::CompanySerializer.new(company).serializable_hash }
        end
      end
    end
  end
end

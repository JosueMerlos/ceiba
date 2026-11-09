module Api
  module V1
    module Modules
      # Activar/desactivar un módulo en la empresa de la ruta y escribir sus settings (docs/architecture/05-module-system.md). La UI
      # llega con M4.01; el contrato ya está aquí. Las acciones exigen `platform.company_module.manage`.
      class CompanyModulesController < ::Api::BaseController
        # PUT .../modules/:key  { "enabled": true|false }
        def update
          authorize company, :update?, policy_class: ::Modules::CompanyModulePolicy
          enabled = ActiveModel::Type::Boolean.new.cast(params.expect(:enabled))
          result = (enabled ? ::Modules::Enable : ::Modules::Disable).call(company:, key: params[:key])
          render json: { data: { key: result.key, enabled:, changed: result.changed } }
        end

        # PATCH .../modules/:key/settings  { "settings": { ... } }
        def update_settings
          authorize company, :update?, policy_class: ::Modules::CompanyModulePolicy
          render_settings(branch: nil)
        end

        # PATCH .../branches/:branch_id/modules/:key/settings  { "settings": { ... } }
        def update_branch_settings
          branch = Current.context.branch
          authorize branch, :update_branch_settings?, policy_class: ::Modules::CompanyModulePolicy
          render_settings(branch:)
        end

        private

        # `settings` debe ser un objeto JSON; el esquema del módulo valida su contenido (por eso to_unsafe_h: no hay strong params que aplicar).
        def settings_param
          settings = params.require(:settings)
          raise ActionController::BadRequest, "settings debe ser un objeto" unless settings.is_a?(ActionController::Parameters)

          settings.to_unsafe_h
        end

        def company = Current.context.company

        def render_settings(branch:)
          settings = ::Modules::UpdateSettings.call(company:, key: params[:key], settings: settings_param, branch:)
          render json: { data: { key: params[:key], settings: } }
        end
      end
    end
  end
end

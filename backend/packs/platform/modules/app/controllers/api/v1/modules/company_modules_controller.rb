module Api
  module V1
    module Modules
      # Enables/disables a module for the route's company and writes its settings. Requires `platform.company_module.manage`.
      class CompanyModulesController < ::Api::BaseController
        def update
          authorize company, :update?, policy_class: ::Modules::CompanyModulePolicy
          enabled = params.expect(:enabled)
          # Only literal JSON true/false: ActiveModel would cast "abc" or "no" to true.
          raise ActionController::BadRequest, "enabled debe ser true o false" unless [ true, false ].include?(enabled)

          result = (enabled ? ::Modules::Enable : ::Modules::Disable).call(company:, key: params[:key])
          render json: { data: { key: result.key, enabled:, changed: result.changed } }
        end

        def update_settings
          authorize company, :update?, policy_class: ::Modules::CompanyModulePolicy
          render_settings(branch: nil)
        end

        def update_branch_settings
          branch = Current.context.branch
          authorize branch, :update_branch_settings?, policy_class: ::Modules::CompanyModulePolicy
          render_settings(branch:)
        end

        private

        # The module's schema validates the content, so strong params do not apply (hence to_unsafe_h).
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

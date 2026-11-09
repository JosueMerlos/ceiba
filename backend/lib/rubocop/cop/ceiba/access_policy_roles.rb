# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Las policies preguntan por PERMISOS (`can?("modulo.recurso.accion", alcance)`), nunca por roles (ADR-0008): un módulo
      # nuevo no debe obligar a tocar policies, y los roles personalizados (P3) no deben romperlas. Prohíbe en
      # `packs/*/*/app/policies`:
      #   - `admin?` y las consultas de rol (`role`, `roles`, `role_key`, `has_role?`, `in_role?`, `memberships`);
      #   - cualquier literal (cadena, símbolo, %w, %i) que sea el nombre de un rol de sistema.
      #
      # @example
      #   # bad
      #   def update? = principal.role == "receptionist" || user.admin?
      #   # good
      #   def update? = can?("appointments.appointment.update", record.branch)
      class AccessPolicyRoles < Base
        MSG = "Las policies preguntan por permisos (`can?`), no por roles: se prohíbe `%<found>s` (ADR-0008, docs/architecture/04-access-control.md)."

        ROLE_KEYS = %w[org_owner org_admin company_manager branch_manager receptionist professional].freeze
        ROLE_QUERIES = %i[admin? role roles role_key role_name role? has_role? in_role? memberships].freeze

        RESTRICT_ON_SEND = ROLE_QUERIES

        def on_send(node)
          add_offense(node.loc.selector, message: format(MSG, found: node.method_name)) if node.receiver || node.method?(:admin?)
        end
        alias on_csend on_send

        def on_str(node)
          check_literal(node, node.value)
        end

        def on_sym(node)
          check_literal(node, node.value.to_s)
        end

        private

        def check_literal(node, value)
          return unless ROLE_KEYS.include?(value)

          add_offense(node, message: format(MSG, found: value))
        end
      end
    end
  end
end

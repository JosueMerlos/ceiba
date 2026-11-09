# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Las policies preguntan por PERMISOS (`can?("modulo.recurso.accion", alcance)`), nunca por roles (ADR-0008): un módulo
      # nuevo no debe obligar a tocar policies, y los roles personalizados (P3) no deben romperlas. Prohíbe en
      # `packs/*/*/app/policies`:
      #   - `admin?` y las consultas de rol (`role`, `roles`, `role_key`, `has_role?`, `in_role?`, `memberships`), también por
      #     `send` / `public_send` / `__send__` con símbolo o cadena;
      #   - `instance_variable_get`: es la puerta para leer el rol sin nombrarlo;
      #   - cualquier literal (cadena, símbolo, %w, %i) que sea el nombre de un rol de sistema, y las formas partidas: cadenas
      #     adyacentes (`"org_" "owner"`), interpolación (`"org_#{x}"`) y concatenación literal (`"recep" + "tionist"`).
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
        DYNAMIC_SENDS = %i[send public_send __send__].freeze
        BACKDOORS = %i[instance_variable_get instance_variable_set].freeze
        MIN_PREFIX = 4

        RESTRICT_ON_SEND = (ROLE_QUERIES + DYNAMIC_SENDS + BACKDOORS + [ :+ ]).freeze

        def on_send(node)
          name = node.method_name
          if DYNAMIC_SENDS.include?(name)
            check_dynamic_send(node)
          elsif BACKDOORS.include?(name)
            add_offense(node.loc.selector, message: format(MSG, found: name))
          elsif name == :+
            check_concatenation(node)
          elsif node.receiver || node.method?(:admin?)
            add_offense(node.loc.selector, message: format(MSG, found: name))
          end
        end
        alias on_csend on_send

        def on_str(node)
          check_literal(node, node.value)
        end

        def on_sym(node)
          check_literal(node, node.value.to_s)
        end

        def on_dstr(node)
          static = node.children.select(&:str_type?).map(&:value).join
          interpolated = node.children.any? { |child| !child.str_type? }
          return unless contains_role?(static) || (interpolated && prefix_of_role?(static))

          add_offense(node, message: format(MSG, found: "una clave de rol construida con cadenas partidas"))
        end

        private

        def check_dynamic_send(node)
          target = node.arguments.first
          return unless target&.type?(:sym, :str) && ROLE_QUERIES.include?(target.value.to_sym)

          add_offense(target, message: format(MSG, found: target.value))
        end

        def check_concatenation(node)
          left = node.receiver
          right = node.first_argument
          return unless left&.str_type? && right&.str_type?

          add_offense(node, message: format(MSG, found: "una clave de rol construida con cadenas partidas")) if contains_role?(left.value + right.value)
        end

        def check_literal(node, value)
          return unless ROLE_KEYS.include?(value)

          add_offense(node, message: format(MSG, found: value))
        end

        def contains_role?(text) = ROLE_KEYS.any? { |key| text.include?(key) }
        def prefix_of_role?(text) = text.length >= MIN_PREFIX && ROLE_KEYS.any? { |key| key.start_with?(text) }
      end
    end
  end
end

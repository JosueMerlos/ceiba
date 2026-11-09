# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # La ÚNICA forma de no autorizar una acción es `skip_authorization!(reason:, only:)` (Access::Authorization): deja el motivo
      # escrito y aparece en la allowlist que vigila spec/requests/api/authorization_spec.rb. Este cop prohíbe en los controladores
      # cualquier otro camino: `skip_after_action :verify_authorized` (o `verify_policy_scoped` / `verify_collection_scoped`),
      # `skip_callback` sobre ellos, redefinirlos, y los `skip_authorization` / `skip_policy_scope` de Pundit.
      class AuthorizationSkips < Base
        MSG = "No te saltes la autorización por tu cuenta: usa `skip_authorization!(reason:, only:)` (queda en la allowlist revisada)."

        VERIFICATIONS = %i[verify_authorized verify_policy_scoped verify_collection_scoped].freeze
        SKIP_CALLBACKS = %i[skip_after_action skip_before_action skip_around_action skip_callback].freeze
        PUNDIT_SKIPS = %i[skip_authorization skip_policy_scope].freeze

        REDEFINERS = %i[define_method alias_method undef_method remove_method instance_variable_set].freeze
        PUNDIT_MARKS = /\A@_pundit_/

        RESTRICT_ON_SEND = (SKIP_CALLBACKS + PUNDIT_SKIPS + REDEFINERS).freeze

        def on_send(node)
          if PUNDIT_SKIPS.include?(node.method_name)
            add_offense(node)
          elsif REDEFINERS.include?(node.method_name)
            add_offense(node) if redefines_verification?(node)
          elsif node.each_descendant(:sym).any? { |sym| VERIFICATIONS.include?(sym.value) }
            add_offense(node)
          end
        end

        # @_pundit_policy_authorized = true (marca de Pundit escrita a mano)
        def on_ivasgn(node)
          add_offense(node) if PUNDIT_MARKS.match?(node.name.to_s)
        end

        def on_def(node)
          add_offense(node.loc.name) if VERIFICATIONS.include?(node.method_name)
        end

        private

        def redefines_verification?(node)
          node.each_descendant(:sym).any? { |sym| VERIFICATIONS.include?(sym.value) || PUNDIT_MARKS.match?(sym.value.to_s) }
        end
      end
    end
  end
end

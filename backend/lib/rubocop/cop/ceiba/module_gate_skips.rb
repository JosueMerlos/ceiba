# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # The 404 of an inactive module is emitted by `ensure_required_module_enabled!` (Modules::RequiresModule). A
      # controller with `requires_module` that skips it (`skip_before_action`, `skip_callback`, redefining it or
      # `self.required_module = nil`) leaves its routes open with the module off. The module coverage suite also detects
      # it at runtime; this cop stops it at write time.
      class ModuleGateSkips < Base
        MSG = "No te saltes el gate del módulo (ensure_required_module_enabled!): un módulo inactivo debe dar 404 en TODAS sus rutas."

        GATE = :ensure_required_module_enabled!
        SKIP_CALLBACKS = %i[skip_before_action skip_around_action skip_after_action skip_callback].freeze
        REDEFINERS = %i[define_method alias_method undef_method remove_method].freeze
        RESTRICT_ON_SEND = (SKIP_CALLBACKS + REDEFINERS + %i[required_module=]).freeze

        def on_send(node)
          if node.method?(:required_module=)
            add_offense(node) if node.first_argument&.nil_type?
          elsif node.each_descendant(:sym, :str).any? { |literal| literal.value.to_s == GATE.to_s }
            add_offense(node)
          end
        end

        def on_def(node)
          add_offense(node.loc.name) if node.method_name == GATE
        end
      end
    end
  end
end

# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Prohíbe saltarse el aislamiento de tenant fuera de una lista de archivos revisada (AllowedFiles)
      # (docs/architecture/03-multi-tenancy.md, "Caminos privilegiados"):
      #
      # - `ActsAsTenant.without_tenant`, `with_mutable_tenant`, `with_tenant`, `current_tenant=`, `unscoped=`:
      #   el tenant solo lo fija `Tenancy.with_context` (que además hace el SET LOCAL de RLS);
      # - `unscoped` (en cualquier receptor): quita el default scope que filtra por organización;
      # - las otras formas de quitar o reemplazar esa condición: `unscope(:where)`/`unscope(where: ...)`, `rewhere(...)`
      #   sobre organization_id, `except(:where)` y `only(...)`;
      # - llegar a lo anterior con `send`/`public_send`/`__send__`, o escribir en `ActsAsTenant::Current`.
      #
      # No cubre SQL crudo (`find_by_sql`, `connection.execute`): eso lo cierra RLS (M4.03).
      #
      # Los caminos legítimos (reportes consolidados, back-office) se añaden a AllowedFiles en .rubocop.yml, con revisión
      # (CODEOWNERS), uno por uno: no se desactiva el cop con comentarios rubocop:disable.
      #
      # @example
      #   # bad
      #   ActsAsTenant.without_tenant { Appointment.count }
      #   Appointment.unscoped.where(id: id)
      #
      #   # good
      #   Tenancy.with_context(organization: organization) { Appointment.count }
      class TenantBypass < Base
        MSG = "`%<method>s` salta el aislamiento de tenant: usa `Tenancy.with_context` " \
              "(o añade el archivo a AllowedFiles tras revisión)."
        ACTS_AS_TENANT_METHODS = %i[
          without_tenant with_mutable_tenant with_tenant current_tenant= unscoped= test_tenant= default_tenant=
        ].freeze
        CURRENT_METHODS = %i[current_tenant= acts_as_tenant_unscoped= acts_as_tenant_mutable= set].freeze
        SEND_METHODS = %i[send public_send __send__].freeze
        # Métodos de relación que quitan/reemplazan la condición del tenant (siempre, o según sus argumentos).
        # Escrituras masivas: se saltan callbacks y validaciones (TenantWriteGuard las acota en ejecución; aquí se revisan).
        BULK_METHODS = %i[upsert_all upsert insert_all insert_all!].freeze
        BULK_ON_CONSTANT_METHODS = %i[insert insert!].freeze # `insert` también existe en Array/String: solo con Constante.insert
        TENANT_COLUMN_WRITERS = %i[update_all update_columns update_column].freeze
        RELATION_METHODS = %i[unscoped unscope rewhere except only].freeze

        # @!method acts_as_tenant_call?(node)
        def_node_matcher :acts_as_tenant_call?, <<~PATTERN
          (send (const {nil? cbase} :ActsAsTenant) _ ...)
        PATTERN

        # @!method acts_as_tenant_current_call?(node)
        def_node_matcher :acts_as_tenant_current_call?, <<~PATTERN
          (send (const (const {nil? cbase} :ActsAsTenant) :Current) _ ...)
        PATTERN

        def on_send(node)
          method = bypass_method(node)
          return unless method
          return if allowed_file?

          add_offense(node, message: format(MSG, method:))
        end

        private

        # Nombre del bypass que el nodo intenta, o nil si es una llamada inocente.
        def bypass_method(node)
          return send_target(node) if SEND_METHODS.include?(node.method_name) && node.first_argument
          return node.method_name if acts_as_tenant_call?(node) && ACTS_AS_TENANT_METHODS.include?(node.method_name)
          return node.method_name if acts_as_tenant_current_call?(node) && CURRENT_METHODS.include?(node.method_name)

          return node.method_name if bulk_write?(node)

          node.method_name if relation_bypass?(node.method_name, node.arguments)
        end

        def bulk_write?(node)
          return true if BULK_METHODS.include?(node.method_name)
          return true if BULK_ON_CONSTANT_METHODS.include?(node.method_name) && node.receiver&.const_type?

          TENANT_COLUMN_WRITERS.include?(node.method_name) && node.arguments.any? { |argument| writes_organization_id?(argument) }
        end

        def writes_organization_id?(node)
          return mentions_organization_id?(node) if node.hash_type?

          (node.sym_type? || node.str_type?) && node.value.to_s.match?(/\borganization_id\b/)
        end

        # `x.send(:unscoped)` / `x.public_send("without_tenant")`: se mira el método destino.
        def send_target(node)
          name = node.first_argument
          return unless name.sym_type? || name.str_type?

          target = name.value.to_sym
          return target if ACTS_AS_TENANT_METHODS.include?(target) && acts_as_tenant_call?(node)

          target if relation_bypass?(target, node.arguments.drop(1))
        end

        def relation_bypass?(method, arguments)
          return false unless RELATION_METHODS.include?(method)

          case method
          when :unscoped, :only then true
          when :unscope, :except then arguments.any? { |argument| mentions_where?(argument) }
          when :rewhere then arguments.any? { |argument| mentions_organization_id?(argument) }
          end
        end

        def mentions_where?(node)
          (node.sym_type? || node.str_type?) && node.value.to_s == "where" ||
            node.hash_type? && node.pairs.any? { |pair| pair.key.respond_to?(:value) && pair.key.value.to_s == "where" }
        end

        def mentions_organization_id?(node)
          node.hash_type? && node.pairs.any? { |pair| pair.key.respond_to?(:value) && pair.key.value.to_s == "organization_id" }
        end

        def allowed_file?
          relative = PathUtil.relative_path(processed_source.file_path.to_s)
          Array(cop_config["AllowedFiles"]).any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end
    end
  end
end

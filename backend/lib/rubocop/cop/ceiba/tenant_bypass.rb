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
      # - `unscoped` (en cualquier receptor): quita el default scope que filtra por organización.
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

        # @!method acts_as_tenant_call?(node)
        def_node_matcher :acts_as_tenant_call?, <<~PATTERN
          (send (const {nil? cbase} :ActsAsTenant) _ ...)
        PATTERN

        def on_send(node)
          return unless bypass?(node)
          return if allowed_file?

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        private

        def bypass?(node)
          node.method?(:unscoped) || (acts_as_tenant_call?(node) && ACTS_AS_TENANT_METHODS.include?(node.method_name))
        end

        def allowed_file?
          relative = PathUtil.relative_path(processed_source.file_path.to_s)
          Array(cop_config["AllowedFiles"]).any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end
    end
  end
end

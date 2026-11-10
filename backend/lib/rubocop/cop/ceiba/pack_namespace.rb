# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # A pack's Ruby namespace is the pack name, no exceptions: `packs/modules/appointments` defines `Appointments::*`.
      # Zeitwerk already requires the file path to match the constant; this cop requires the constant to start with the
      # pack the file belongs to, so a file cannot "sneak" into another pack's namespace or sit without one.
      #
      # Controllers may hang from `Api::V1::<Pack>` (routes under /api/v1).
      #
      # @example
      #   # bad (packs/modules/appointments/app/models/appointments/booking.rb)
      #   class Booking < ApplicationRecord; end
      #
      #   # good
      #   module Appointments
      #     class Booking < ApplicationRecord; end
      #   end
      class PackNamespace < Base
        PACK_PATH = %r{\A(?<root>.*?packs/[^/]+/(?<name>[^/]+))/app/(?<kind>[^/]+)/}

        def on_new_investigation
          match = PACK_PATH.match(processed_source.file_path.to_s)
          return unless match

          @namespaces = allowed_namespaces(match[:name], match[:kind])
          @pack = match[:root].sub(%r{\A.*?(?=packs/)}, "")
          check_definitions(top_level_nodes, nil)
        end

        MSG = "El namespace debe empezar por `%<namespace>s` (pack %<pack>s)."

        private

        def allowed_namespaces(pack_name, kind)
          namespace = pack_name.split("_").map(&:capitalize).join
          kind == "controllers" ? [ namespace, "Api::V1::#{namespace}" ] : [ namespace ]
        end

        def top_level_nodes
          root = processed_source.ast
          return [] unless root

          root.begin_type? ? root.children : [ root ]
        end

        # Walks ALL definitions. Each is resolved against its enclosing namespace (`::X` is absolute) and must end up
        # inside the pack; the only outsiders admitted are modules on the way to it (`Api`, `Api::V1` for
        # `Api::V1::Pack` in controllers).
        def check_definitions(nodes, parent)
          nodes.each do |node|
            next unless node.is_a?(RuboCop::AST::Node)
            next check_definitions(node.children, parent) if node.begin_type?
            next unless node.module_type? || node.class_type?

            name = qualified_name(node.identifier.source, parent)
            if acceptable?(name)
              check_definitions(node.each_child_node.to_a, name)
            else
              add_offense(node.identifier, message: format(MSG, namespace: @namespaces.first, pack: @pack))
            end
          end
        end

        def qualified_name(source, parent)
          return source.delete_prefix("::") if source.start_with?("::") || parent.nil?

          "#{parent}::#{source}"
        end

        def acceptable?(name)
          @namespaces.any? do |namespace|
            name == namespace || name.start_with?("#{namespace}::") || namespace.start_with?("#{name}::")
          end
        end
      end
    end
  end
end

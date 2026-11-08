# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # El namespace Ruby de un pack es el nombre del pack, sin excepción
      # (docs/architecture/02-modular-monolith.md): `packs/modules/appointments` define `Appointments::*`.
      # Zeitwerk ya exige que la ruta del archivo coincida con la constante; este cop exige que esa
      # constante empiece por el pack al que pertenece el archivo, así un archivo no puede "colarse"
      # en el namespace de otro pack ni quedar sin namespace.
      #
      # Los controladores pueden colgar de `Api::V1::<Pack>` (rutas bajo /api/v1).
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

        # Recorre TODAS las definiciones. Cada una se resuelve contra el namespace que la envuelve
        # (`::X` es absoluto) y debe quedar dentro del pack; solo se admiten, sin estar dentro, los
        # módulos que son camino hacia él (`Api`, `Api::V1` para `Api::V1::Pack` en controladores).
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

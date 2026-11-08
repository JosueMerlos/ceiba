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

          namespaces = allowed_namespaces(match[:name], match[:kind])
          top_level_definitions.each do |definition|
            next if nested_names(definition).any? { |name| inside_any?(name, namespaces) }

            add_offense(definition.identifier,
                        message: format(MSG, namespace: namespaces.first, pack: match[:root].sub(%r{\A.*?(?=packs/)}, "")))
          end
        end

        MSG = "El namespace debe empezar por `%<namespace>s` (pack %<pack>s)."

        private

        def allowed_namespaces(pack_name, kind)
          namespace = pack_name.split("_").map(&:capitalize).join
          kind == "controllers" ? [ namespace, "Api::V1::#{namespace}" ] : [ namespace ]
        end

        def top_level_definitions
          root = processed_source.ast
          return [] unless root

          nodes = root.begin_type? ? root.children : [ root ]
          nodes.select { |node| node.module_type? || node.class_type? }
        end

        # Nombres completos que se alcanzan al anidar: `module Api; module V1` -> "Api", "Api::V1".
        def nested_names(definition, prefix = nil)
          name = [ prefix, definition.identifier.source.delete_prefix("::") ].compact.join("::")
          children = definition.each_child_node(:module, :class, :begin).flat_map do |child|
            child.begin_type? ? child.each_child_node(:module, :class).to_a : [ child ]
          end
          [ name ] + children.flat_map { |child| nested_names(child, name) }
        end

        def inside_any?(name, namespaces)
          namespaces.any? { |namespace| name == namespace || name.start_with?("#{namespace}::") }
        end
      end
    end
  end
end

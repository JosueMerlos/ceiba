module Api
  module Pagination
    # Paginación por cursor sobre la clave primaria (UUIDv7, docs/architecture/09-data-conventions.md). Nada de OFFSET.
    #
    #   page = Api::Pagination::Cursor.paginate(Tenancy::Company.all, limit: params[:limit], after: params[:after])
    #   page.records   # como mucho `limit` filas, en orden ascendente de id
    #   page.meta      # { next_cursor:, has_more: }
    #
    # Por qué es estable: el UUIDv7 lleva el instante de creación en sus primeros bits, así que ordenar por id es
    # ordenar por creación. Una fila insertada entre dos páginas tiene un id MAYOR que todas las ya entregadas: aparece
    # al final del recorrido y nunca desplaza lo que ya se vio (con OFFSET, una inserción duplica u omite filas).
    #
    # El cursor es `{ id }` FIRMADO (MessageVerifier, propósito propio, URL-safe): el cliente no puede fabricar uno ni
    # alterarlo, y no debe interpretarlo. Se piden `limit + 1` filas para saber si hay más sin contar.
    #
    # El orden del scope recibido se DESCARTA (reorder por id); sus filtros se conservan.
    class Cursor
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      PURPOSE = :cursor

      def self.paginate(scope, limit: nil, after: nil) = new(scope, limit:, after:).page

      def self.verifier
        @verifier ||= ActiveSupport::MessageVerifier.new(
          Rails.application.key_generator.generate_key("api.pagination.cursor"), url_safe: true, serializer: JSON
        )
      end
      private_class_method :verifier

      def initialize(scope, limit:, after:)
        @scope = scope
        @limit = parse_limit(limit)
        @after_id = after.nil? ? nil : decode(after)
      end

      def page
        rows = ordered_scope.limit(@limit + 1).to_a
        has_more = rows.size > @limit
        records = rows.first(@limit)
        Page.new(records:, has_more:, next_cursor: has_more ? encode(records.last.id) : nil)
      end

      private

      def ordered_scope
        key = @scope.klass.primary_key
        ordered = @scope.reorder(key => :asc)
        return ordered unless @after_id

        ordered.where(@scope.klass.arel_table[key].gt(@after_id))
      end

      def parse_limit(value)
        return DEFAULT_LIMIT if value.nil?

        number = value.is_a?(Integer) ? value : (Integer(value, 10) if value.is_a?(String) && value.match?(/\A\d+\z/))
        raise InvalidLimit, "limit debe ser un entero entre 1 y #{MAX_LIMIT}" unless number&.between?(1, MAX_LIMIT)

        number
      end

      def encode(id) = self.class.send(:verifier).generate({ "id" => id }, purpose: PURPOSE)

      def decode(cursor)
        payload = cursor.is_a?(String) ? self.class.send(:verifier).verified(cursor, purpose: PURPOSE) : nil
        id = payload["id"] if payload.is_a?(Hash)
        raise InvalidCursor, "cursor inválido" unless id.is_a?(String) && UUID.match?(id)

        id
      end
    end
  end
end

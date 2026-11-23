module Api
  module Pagination
    # Cursor pagination over the primary key (UUIDv7). No OFFSET.
    #
    #   page = Api::Pagination::Cursor.paginate(Tenancy::Company.all, limit: params[:limit], after: params[:after])
    #   page.records   # at most `limit` rows, ascending id order
    #   page.meta      # { next_cursor:, has_more: }
    #
    # Why it is stable: a UUIDv7 carries the creation instant in its first bits, so ordering by id is ordering by
    # creation. A row committed BEFORE the traversal starts is neither duplicated nor skipped when others are inserted
    # between pages (with OFFSET an insert would shift rows). Known limit: the id is generated at INSERT, not COMMIT,
    # and PostgreSQL's uuidv7() is only monotonic within a session; a CONCURRENTLY INSERTED row (or one with an explicit
    # id) may get an id below the cursor and miss this traversal. It shows up in the next one. This is a listing's
    # guarantee, not an event log's.
    #
    # The cursor is a SIGNED `{ id }` (MessageVerifier, own purpose, URL-safe): the client cannot forge or alter it, and
    # must not interpret it. `limit + 1` rows are requested to know whether there are more without counting.
    #
    # The incoming scope's order is DISCARDED (reorder by id); its filters are kept.
    #
    # `order: { starts_at: :desc }` pages by that column instead (keyset over the column and the id, the id breaking ties
    # in the same direction). Its cursor carries both values and does not work on a listing without that order.
    class Cursor
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      PURPOSE = :cursor

      def self.paginate(scope, limit: nil, after: nil, order: nil) = new(scope, limit:, after:, order:).page

      # The page size a client asked for, shared with the listings that paginate by another key.
      def self.parse_limit(value)
        return DEFAULT_LIMIT if value.nil?

        number = value.is_a?(Integer) ? value : (Integer(value, 10) if value.is_a?(String) && value.match?(/\A\d+\z/))
        raise InvalidLimit, "limit debe ser un entero entre 1 y #{MAX_LIMIT}" unless number&.between?(1, MAX_LIMIT)

        number
      end

      def self.verifier
        @verifier ||= ActiveSupport::MessageVerifier.new(
          Rails.application.key_generator.generate_key("api.pagination.cursor"), url_safe: true, serializer: JSON
        )
      end
      private_class_method :verifier

      def initialize(scope, limit:, after:, order: nil)
        @scope = scope
        @limit = self.class.parse_limit(limit)
        @column, @direction = order&.first
        @after = after.nil? ? nil : decode(after)
      end

      def page
        rows = ordered_scope.limit(@limit + 1).to_a
        has_more = rows.size > @limit
        records = rows.first(@limit)
        Page.new(records:, has_more:, next_cursor: has_more ? encode(records.last) : nil)
      end

      private

      def ordered_scope
        return keyset_scope if @column

        key = @scope.klass.primary_key
        ordered = @scope.reorder(key => :asc)
        return ordered unless @after

        ordered.where(@scope.klass.arel_table[key].gt(@after.fetch("id")))
      end

      def keyset_scope
        key = @scope.klass.primary_key
        ordered = @scope.reorder(@column => @direction, key => @direction)
        return ordered unless @after

        table = @scope.klass.quoted_table_name
        column = @scope.klass.connection.quote_column_name(@column)
        id = @scope.klass.connection.quote_column_name(key)
        comparison = @direction == :desc ? "<" : ">"
        ordered.where("(#{table}.#{column}, #{table}.#{id}) #{comparison} (?, ?)", @after.fetch("value"), @after.fetch("id"))
      end

      def encode(record)
        payload = { "id" => record.id }
        payload["value"] = cursor_value(record.public_send(@column)) if @column
        self.class.send(:verifier).generate(payload, purpose: PURPOSE)
      end

      # Times keep their microseconds: JSON's default milliseconds would skip rows that differ by less.
      def cursor_value(value) = value.respond_to?(:utc) ? value.utc.iso8601(6) : value.as_json

      def decode(cursor)
        payload = cursor.is_a?(String) ? self.class.send(:verifier).verified(cursor, purpose: PURPOSE) : nil
        id = payload["id"] if payload.is_a?(Hash)
        raise InvalidCursor, "cursor inválido" unless id.is_a?(String) && UUID.match?(id)
        return { "id" => id } unless @column

        value = @scope.klass.type_for_attribute(@column.to_s).cast(payload["value"])
        raise InvalidCursor, "cursor inválido" if value.nil?

        { "id" => id, "value" => value }
      end
    end
  end
end

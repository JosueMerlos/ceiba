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

module Appointments
  # One customer's appointments, newest first, paginated by keyset over (starts_at, id): the shared cursor only walks ids upwards.
  # The cursor is signed with its own purpose so the client cannot forge or alter it; a tie on starts_at is broken by id.
  class CustomerHistory
    PURPOSE = :customer_history_cursor

    def self.page(scope, limit: nil, after: nil) = new(scope, limit:, after:).page

    def self.verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("appointments.customer_history.cursor"), url_safe: true, serializer: JSON
      )
    end

    def initialize(scope, limit:, after:)
      @scope = scope
      @limit = Api::Pagination::Cursor.parse_limit(limit)
      @after = after.nil? ? nil : decode(after)
    end

    def page
      rows = ordered.limit(@limit + 1).to_a
      records = rows.first(@limit)
      has_more = rows.size > @limit
      Api::Pagination::Page.new(records:, has_more:, next_cursor: has_more ? encode(records.last) : nil)
    end

    private

    def ordered
      relation = @scope.reorder(starts_at: :desc, id: :desc)
      return relation unless @after

      starts_at, id = @after
      relation.where("(appointments.starts_at, appointments.id) < (?, ?)", starts_at, id)
    end

    def encode(record) = self.class.verifier.generate([ record.starts_at.utc.iso8601(6), record.id ], purpose: PURPOSE)

    def decode(cursor)
      payload = cursor.is_a?(String) ? self.class.verifier.verified(cursor, purpose: PURPOSE) : nil
      starts_at, id = payload if payload.is_a?(Array) && payload.size == 2
      raise Api::Pagination::InvalidCursor, "cursor inválido" unless id.is_a?(String) && id.match?(Api::Pagination::Cursor::UUID)

      [ Time.iso8601(starts_at), id ]
    rescue ArgumentError, TypeError
      raise Api::Pagination::InvalidCursor, "cursor inválido"
    end
  end
end

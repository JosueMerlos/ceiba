module Events
  class Publisher
    def self.call(...) = new(...).call

    def initialize(name:, payload:, metadata:)
      @name = name.to_s
      @payload = payload
      @metadata = metadata
    end

    # Order: schema (publisher programming error, the same in any context) -> transaction -> insert.
    def call
      normalized = Schemas.validate!(@name, @payload)
      raise NotInTransaction, @name unless ApplicationRecord.connection.transaction_open?

      record = OutboxEvent.create!(name: @name, payload: normalized, metadata: context_metadata.merge(@metadata.as_json), occurred_at: Time.current)
      RelayKick.schedule
      record.to_event
    end

    private

    # Company and branch from the tenancy context. The actor and request_id arrive with the session via `metadata:`.
    def context_metadata
      context = Current.context
      return {} unless context

      { "company_id" => context.company&.id, "branch_id" => context.branch&.id }.compact
    end
  end
end

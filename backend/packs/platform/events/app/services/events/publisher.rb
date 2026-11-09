module Events
  # Implementación de Events.publish (privada del pack).
  class Publisher
    def self.call(...) = new(...).call

    def initialize(name:, payload:, metadata:)
      @name = name.to_s
      @payload = payload
      @metadata = metadata
    end

    # Orden: esquema (error de programación del publicador, igual en cualquier contexto) -> transacción -> inserción.
    def call
      normalized = Schemas.validate!(@name, @payload)
      raise NotInTransaction, @name unless ApplicationRecord.connection.transaction_open?

      record = OutboxEvent.create!(name: @name, payload: normalized, metadata: context_metadata.merge(@metadata.as_json), occurred_at: Time.current)
      RelayKick.schedule
      record.to_event
    end

    private

    # Empresa y sucursal del contexto de tenancy. El actor y el request_id llegan con la sesión (M0.07) vía `metadata:`.
    def context_metadata
      context = Current.context
      return {} unless context

      { "company_id" => context.company&.id, "branch_id" => context.branch&.id }.compact
    end
  end
end

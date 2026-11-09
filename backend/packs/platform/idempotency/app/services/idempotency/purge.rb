module Idempotency
  # Retención de idempotency_keys: una clave vencida (24 h) ya no sirve y guarda una respuesta de negocio. Se borra por lotes
  # (sin una transacción gigante ni bloqueos largos), de todas las organizaciones.
  module Purge
    BATCH_SIZE = 1_000

    module_function

    # Devuelve cuántas filas borró.
    def expired(now: Time.current)
      total = 0
      CrossTenant.run do
        loop do
          deleted = Key.where(id: Key.expired(now).limit(BATCH_SIZE).select(:id)).delete_all
          total += deleted
          break if deleted < BATCH_SIZE
        end
      end
      total
    end
  end
end

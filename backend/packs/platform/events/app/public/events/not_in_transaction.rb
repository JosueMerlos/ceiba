module Events
  # Events.publish called outside a transaction: the event would not be atomic with the data change.
  class NotInTransaction < Error
    def initialize(name = nil)
      super("Events.publish#{" (#{name})" if name} debe llamarse dentro de una transacción: el evento se escribe en la misma transacción que el cambio de datos")
    end
  end
end

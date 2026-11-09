module Events
  # Events.publish llamado fuera de una transacción: el evento no sería atómico con el cambio de datos.
  class NotInTransaction < Error
    def initialize(name = nil)
      super("Events.publish#{" (#{name})" if name} debe llamarse dentro de una transacción: el evento se escribe en la misma transacción que el cambio de datos")
    end
  end
end

module Audit
  # Fila de audit_events. Modelo PRIVADO del pack: se escribe con Audit.record. Tabla tenant, de solo inserción: el
  # trigger de PostgreSQL rechaza UPDATE/DELETE/TRUNCATE y, además, el modelo es de solo lectura una vez guardado.
  class Event < ApplicationRecord
    self.table_name = "audit_events"

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :actor_type, :action, :auditable_type, :auditable_id, presence: true

    def readonly? = persisted? || super
  end
end

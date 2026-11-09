module Events
  # El evento tal como lo ven publicadores y suscriptores: inmutable y sin exponer la fila del outbox.
  Event = Data.define(:id, :name, :organization_id, :payload, :metadata, :occurred_at)
end

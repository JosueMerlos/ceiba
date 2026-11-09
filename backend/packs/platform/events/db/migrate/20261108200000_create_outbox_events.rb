# outbox_events: el evento se escribe en la MISMA transacción del caso de uso (docs/architecture/06-events-and-jobs.md).
#
# Tabla tenant: todo evento pertenece a una organización y su suscriptor corre en ese contexto. El relay, que lee
# pendientes de todas las organizaciones, es un camino privilegiado explícito (Events::Relay, AllowedFiles del cop
# Ceiba/TenantBypass), y con RLS (M4.03) usará el rol privilegiado.
#
# `name` es el nombre completo y versionado (`platform.organization_provisioned.v1`): la versión va dentro, no en una
# columna aparte que pudiera contradecirlo.
class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :outbox_events do |t|
      t.string :name, null: false
      t.jsonb :payload, null: false, default: {}
      # actor, request_id, company_id, branch_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :published_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps

      t.check_constraint "name ~ '^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*\\.v[0-9]+$'", name: "chk_outbox_events_name_format"
      # Lo que recorre el relay: pendientes por id (UUIDv7: orden de creación). Se vacía a medida que se publica.
      t.index :id, where: "published_at IS NULL", name: "idx_outbox_events_pending"
      # Purga de publicados antiguos.
      t.index :published_at, where: "published_at IS NOT NULL", name: "idx_outbox_events_published_at"
    end
  end
end

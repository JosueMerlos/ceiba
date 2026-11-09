# idempotency_keys: respuestas guardadas para que reintentar una creación sea seguro (docs/architecture/07-api-contract.md).
# Tabla TENANT. Única por (organización, principal, clave): la clave de un principal nunca repite la respuesta de otro.
#
# - `principal_key`: "user:<uuid>", "api_key:<uuid>"... o "anonymous" (reserva pública, sin sesión). Una sola columna de
#   texto y no (type, id) porque un UNIQUE no trata los NULL como iguales y el anónimo no tiene id.
# - `request_fingerprint`: SHA-256 de método + ruta + cuerpo. Misma clave y otro fingerprint => 409.
# - `response_*` son NULL mientras la petición se procesa (la reserva vive dentro de la transacción del request: nadie más
#   la ve hasta el commit, y un rollback la elimina).
# - `expires_at`: 24 h. Las filas vencidas se ignoran y se reemplazan al reutilizar la clave; la purga masiva no se pide en M0.11.
class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :idempotency_keys do |t|
      t.string :principal_key, null: false
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.integer :response_status
      t.text :response_body
      t.jsonb :response_headers, null: false, default: {}
      t.string :content_type
      t.datetime :expires_at, null: false
      t.timestamps

      t.index %i[organization_id principal_key key], unique: true, name: "uq_idempotency_keys_scope"
      t.index :expires_at, name: "idx_idempotency_keys_expires_at"
    end
  end
end

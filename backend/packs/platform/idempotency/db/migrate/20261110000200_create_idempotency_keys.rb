# idempotency_keys: stored responses so that retrying a creation is safe. TENANT table, unique per (organization,
# principal, key): one principal's key never replays another's response.
#
# - `principal_key`: "user:<uuid>", "api_key:<uuid>"... or "anonymous" (public booking, no session). A single text
#   column rather than (type, id) because a UNIQUE does not treat NULLs as equal and anonymous has no id.
# - `request_fingerprint`: SHA-256 of method + path + body. Same key and another fingerprint => 409.
# - `response_*` are NULL while the request is processing (the reservation lives inside the request's transaction:
#   nobody else sees it until commit, and a rollback removes it).
# - `expires_at`: 24 h. Expired rows are ignored and replaced when the key is reused.
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

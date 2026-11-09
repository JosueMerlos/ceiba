# Sesiones del panel (ADR-0017, docs/architecture/11-security.md). El token NUNCA se guarda: solo su digest SHA-256
# (único: es la clave de búsqueda). Global, no tenant: una sesión es de la persona, no de una organización (ADR-0028).
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.string :token_digest, null: false, index: { unique: true }
      t.inet :ip
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
  end
end

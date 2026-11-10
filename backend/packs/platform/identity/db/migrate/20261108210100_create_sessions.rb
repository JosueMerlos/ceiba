# Panel sessions. The token is NEVER stored: only its SHA-256 digest (unique: it is the lookup key). Global, not tenant:
# a session belongs to the person, not to an organization.
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

# users es GLOBAL (ADR-0028): no lleva organization_id ni política RLS; la pertenencia a organizaciones la dan los
# memberships (M0.08). El correo es citext: único sin distinguir mayúsculas (docs/architecture/09-data-conventions.md).
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.citext :email, null: false
      t.string :password_digest, null: false
      t.string :full_name, null: false
      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end

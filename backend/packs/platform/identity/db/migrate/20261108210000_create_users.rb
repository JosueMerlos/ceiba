# users is GLOBAL: no organization_id or RLS policy; organization membership comes from memberships. The email is
# citext: unique regardless of case.
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

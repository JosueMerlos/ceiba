# flipper-active_record tables (per-organization feature flags). GLOBAL, not tenant: a flag is a development decision ("have we
# released this to this organization yet?"), and the `organization` actor lives inside `gates.value` ("Organization;<id>"),
# not in an organization_id column. Same schema as `flipper:setup`, with uuid (uuidv7) PKs like the rest.
class CreateFlipperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :flipper_features, id: :uuid do |t|
      t.string :key, null: false
      t.timestamps null: false
      t.index :key, unique: true
    end

    create_table :flipper_gates, id: :uuid do |t|
      t.string :feature_key, null: false
      t.string :key, null: false
      t.text :value
      t.timestamps null: false
      t.index %i[feature_key key value], unique: true, length: { value: 255 }
    end
  end
end

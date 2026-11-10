# Tablas de flipper-active_record (feature flags por organización, M0.09). GLOBALES, no tenant: un flag es una decisión de
# desarrollo ("¿ya liberamos esto para esta organización?"), y el actor `organization` va dentro de `gates.value`
# ("Organization;<id>"), no en una columna organization_id. Mismo esquema que `flipper:setup`, con PK uuid (uuidv7) como el resto.
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

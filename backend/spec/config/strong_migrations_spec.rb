require "rails_helper"

# Criterio 4 de M0.04: una migración que agrega un índice sin `algorithm: :concurrently` la bloquea
# strong_migrations. Estos specs corren en CI (backend-test), así que una migración peligrosa no llega a main.
RSpec.describe "strong_migrations" do
  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }

  def migration_class(&body)
    Class.new(ActiveRecord::Migration[8.1]) { define_method(:change, &body) }
  end

  # `migrate` es el punto donde strong_migrations registra la dirección y comprueba cada comando.
  def run_up(migration) = migration.new.migrate(:up)

  it "se ajusta a PostgreSQL 18" do
    expect(StrongMigrations.target_version).to eq(18)
  end

  it "fija timeouts de bloqueo y de sentencia durante las migraciones" do
    expect(StrongMigrations.lock_timeout).to be_present
    expect(StrongMigrations.statement_timeout).to be_present
    expect(StrongMigrations.lock_timeout).to be < StrongMigrations.statement_timeout
  end

  it "bloquea agregar un índice sin algorithm: :concurrently" do
    unsafe = migration_class { add_index :strong_probes, :name }

    expect { run_up(unsafe) }.to raise_error(StrongMigrations::UnsafeMigration, /concurrently/)
  end

  it "permite el índice concurrente en una migración sin transacción DDL" do
    OwnerConnection.with do |owner|
      owner.create_table(:strong_probes) { |t| t.string :name }
      begin
        safe = Class.new(ActiveRecord::Migration[8.1]) do
          disable_ddl_transaction!
          def change = add_index(:strong_probes, :name, algorithm: :concurrently)
        end

        expect { safe.new.exec_migration(owner, :up) }.not_to raise_error
        expect(owner.index_exists?(:strong_probes, :name)).to be(true)
      ensure
        owner.drop_table(:strong_probes, if_exists: true)
      end
    end
  end
end

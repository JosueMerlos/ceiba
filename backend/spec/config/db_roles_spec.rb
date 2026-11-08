require "rails_helper"
require Rails.root.join("config/db_roles").to_s

# Allowlist explícita de tareas que corren como app_owner (config/db_roles.rb). Todo lo demás, app_user.
RSpec.describe DbRoles do
  describe ".select" do
    %w[db:create db:drop db:migrate db:migrate:up db:migrate:down db:migrate:redo db:rollback db:forward db:reset db:setup
       db:prepare db:schema:load db:schema:dump db:structure:load db:environment:set db:test:prepare db:test:load_schema
       db:test:purge db:migrate:primary db:create:all].each do |task|
      it "#{task} corre como owner" do
        expect(described_class.select([ task ])).to eq("owner")
      end
    end

    it "ignora los argumentos de la tarea (db:migrate[20260101])" do
      expect(described_class.select([ "db:migrate[20260101000000]" ])).to eq("owner")
    end

    %w[db:seed db:seed:replant db:fixtures:load db:truncate_all db:migrate:status db:version db:abort_if_pending_migrations
       server console runner spec ceiba:custom db:custom_data_fix].each do |task|
      it "#{task} (no listada) corre como user" do
        expect(described_class.select([ task ])).to eq("user")
      end
    end

    it "sin tareas (servidor, worker, consola, rspec) usa user" do
      expect(described_class.select([])).to eq("user")
    end

    it "si alguna tarea de la invocación está en la allowlist usa owner" do
      expect(described_class.select(%w[db:migrate db:seed])).to eq("owner")
    end

    it "DB_ROLE sobrescribe en ambos sentidos" do
      expect(described_class.select([ "db:migrate" ], "user")).to eq("user")
      expect(described_class.select([ "db:seed" ], "owner")).to eq("owner")
    end

    it "rechaza un DB_ROLE desconocido" do
      expect { described_class.select([], "admin") }.to raise_error(/DB_ROLE inválido/)
    end
  end
end

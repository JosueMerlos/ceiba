require "rails_helper"

RSpec.describe ReadinessCheck do
  subject(:check) { described_class.new(redis_url:, database_config:) }

  let(:redis_url) { Rails.configuration.x.redis_url }
  let(:database_config) { ActiveRecord::Base.connection_db_config.configuration_hash }

  describe "#call" do
    context "con PostgreSQL y Redis sanos" do
      it "está listo" do
        result = check.call

        expect(result).to be_ready
        expect(result.to_h).to eq(status: "ok", checks: { database: "ok", redis: "ok" })
      end
    end

    context "con Redis caído" do
      let(:redis_url) { "redis://127.0.0.1:1/0" }

      it "marca solo Redis como no disponible" do
        expect(check.call.to_h).to eq(status: "unavailable", checks: { database: "ok", redis: "unavailable" })
      end
    end

    context "con PostgreSQL caído" do
      let(:database_config) { super().merge(host: "127.0.0.1", port: 1) }

      it "marca solo PostgreSQL como no disponible" do
        expect(check.call.to_h).to eq(status: "unavailable", checks: { database: "unavailable", redis: "ok" })
      end
    end

    context "cuando PostgreSQL acepta la conexión TCP pero nunca responde" do
      it "no está listo y termina antes de 3 s" do
        with_blackhole do |port|
          check = described_class.new(redis_url:, database_config: database_config.merge(host: "127.0.0.1", port:))
          result = nil

          expect(elapsed_seconds { result = check.call }).to be < 3
          expect(result.checks).to include(database: false, redis: true)
        end
      end
    end

    context "cuando Redis acepta la conexión TCP pero nunca responde" do
      it "no está listo y termina antes de 3 s" do
        with_blackhole do |port|
          check = described_class.new(redis_url: "redis://127.0.0.1:#{port}/0", database_config:)
          result = nil

          expect(elapsed_seconds { result = check.call }).to be < 3
          expect(result.checks).to include(database: true, redis: false)
        end
      end
    end

    context "cuando PostgreSQL conecta bien pero SELECT 1 se cuelga" do
      let(:connection) { instance_double(PG::Connection, close: nil) }

      before do
        allow(PG).to receive(:connect).and_return(connection)
        allow(connection).to receive(:exec).with("SELECT 1") { sleep 10 }
      end

      it "no está listo y termina antes de 3 s" do
        result = nil

        expect(elapsed_seconds { result = check.call }).to be < 3
        expect(result.checks).to include(database: false, redis: true)
      end

      it "cierra la conexión efímera aunque el timeout interrumpa la consulta" do
        check.call

        expect(connection).to have_received(:close)
      end
    end

    context "al comprobar PostgreSQL" do
      it "abre y cierra su propia conexión sin tocar el pool de Active Record" do
        pool = spy_on_connection_pool
        connection = nil
        allow(PG).to receive(:connect).and_wrap_original do |original, *args|
          connection = original.call(*args)
          allow(connection).to receive(:close).and_call_original
          connection
        end

        check.call

        expect(connection).to have_received(:close)
        expect_connection_pool_untouched(pool)
      end

      it "el espía del pool detecta el uso real del pool (control positivo)" do
        pool = spy_on_connection_pool

        ActiveRecord::Base.with_connection { |conn| conn.select_value("SELECT 1") }

        expect(pool).to have_received(:with_connection)
      end
    end

    context "cuando un servicio falla" do
      let(:redis_url) { "redis://127.0.0.1:1/0" }

      it "registra la clase del error sin volcar detalles internos" do
        allow(Rails.logger).to receive(:warn)

        check.call

        expect(Rails.logger).to have_received(:warn).with(/redis no responde \(\w+(::\w+)*\)\z/)
      end
    end
  end
end

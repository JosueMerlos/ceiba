require "rails_helper"

# `read_only: true` convierte la transacción del contexto en SOLO LECTURA (SET TRANSACTION READ ONLY): una lectura (GET) no puede
# escribir ni por error, y la transacción larga de una request de lectura es más barata. Sin fixtures transaccionales: el BEGIN
# y el COMMIT son reales.
RSpec.describe "Tenancy.with_context(read_only: true)" do
  self.use_transactional_tests = false

  let!(:organization) { Tenancy::Organization.create!(name: "Solo lectura") }

  after do
    Tenancy.with_context(organization:) { Tenancy::Company.delete_all }
    Tenancy::Organization.where(id: organization.id).delete_all
  end

  def read_only_setting = ApplicationRecord.connection.select_value("SHOW transaction_read_only")

  it "dentro del bloque la transacción es de solo lectura" do
    inside = Tenancy.with_context(organization:, read_only: true) { read_only_setting }

    expect(inside).to eq("on")
  end

  it "una escritura dentro del bloque falla en la BASE (ReadOnlySqlTransaction), aunque el código la intente" do
    expect do
      Tenancy.with_context(organization:, read_only: true) { Tenancy::Company.create!(name: "X", slug: "solo-lectura-x", business_type: "salon", currency: "NIO") }
    end.to raise_error(ActiveRecord::StatementInvalid, /read-only transaction/)
  end

  it "al salir, la conexión vuelve a escribir (el modo no se filtra al pool)" do
    Tenancy.with_context(organization:, read_only: true) { nil }

    expect(read_only_setting).to eq("off")
    expect { Tenancy.with_context(organization:) { Tenancy::Company.create!(name: "Y", slug: "solo-lectura-y", business_type: "salon", currency: "NIO") } }.not_to raise_error
  end

  it "sin read_only (por defecto) la transacción escribe" do
    expect(Tenancy.with_context(organization:) { read_only_setting }).to eq("off")
  end

  it "dentro de una transacción ajena NO se cambia el modo de esa transacción (solo el contexto más externo lo fija)" do
    ApplicationRecord.transaction do
      inside = Tenancy.with_context(organization:, read_only: true) { read_only_setting }

      expect(inside).to eq("off")
    end
  end

  it "un contexto anidado dentro de uno de solo lectura sigue siendo de solo lectura" do
    inner = Tenancy.with_context(organization:, read_only: true) { Tenancy.with_context(organization:) { read_only_setting } }

    expect(inner).to eq("on")
  end
end

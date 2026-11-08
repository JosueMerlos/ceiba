require "rails_helper"

# Guardián: las tablas con columna organization_id son EXACTAMENTE las registradas como tenant (política
# tenant_isolation), en ambos sentidos. Una tabla creada con create_table normal + organization_id queda sin RLS
# ni FK compuesta: aquí se detecta. Exentas solo las justificadas en EXEMPT (hoy ninguna).
RSpec.describe Database::TenantTables, :tenant_schema do
  let(:exempt) { {} } # tabla => motivo; vacío: ninguna tabla está exenta

  it "el esquema real es consistente: organization_id <=> tabla registrada" do
    problems = described_class.inconsistencies(ActiveRecord::Base.connection, exempt: exempt.keys)

    expect(problems).to eq(unregistered: [], without_organization_id: [])
  end

  it "detecta una tabla con organization_id creada con create_table normal" do
    with_tenant_schema do |owner|
      owner.create_table(:sneaky) { |t| t.uuid :organization_id }

      expect(described_class.inconsistencies(owner)).to include(unregistered: [ "sneaky" ])
    end
  end

  it "detecta una tabla registrada a la que le falta organization_id" do
    with_tenant_schema do |owner|
      owner.create_table(:odd)
      owner.execute("CREATE POLICY tenant_isolation ON odd USING (true)")

      expect(described_class.inconsistencies(owner)).to include(without_organization_id: [ "odd" ])
    end
  end

  it "ve también las tablas sin privilegios para el rol de la aplicación (no depende de information_schema)" do
    OwnerConnection.with do |owner|
      owner.execute("DROP TABLE IF EXISTS sneaky_ungranted")
      owner.execute("CREATE TABLE sneaky_ungranted (organization_id uuid)")
      owner.execute("REVOKE ALL ON sneaky_ungranted FROM app_user")
      begin
        expect(described_class.inconsistencies(ActiveRecord::Base.connection)).to include(unregistered: [ "sneaky_ungranted" ])
      ensure
        owner.execute("DROP TABLE IF EXISTS sneaky_ungranted")
      end
    end
  end

  it "respeta las exenciones" do
    with_tenant_schema do |owner|
      owner.create_table(:sneaky) { |t| t.uuid :organization_id }

      expect(described_class.inconsistencies(owner, exempt: [ "sneaky" ])).to eq(unregistered: [], without_organization_id: [])
    end
  end

  it "no marca las tablas tenant bien creadas ni organizations" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:branches)

      expect(described_class.inconsistencies(owner)).to eq(unregistered: [], without_organization_id: [])
    end
  end
end

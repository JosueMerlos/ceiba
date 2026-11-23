require "rails_helper"

RSpec.describe Imports::CreateBatch do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:user_id) { SecureRandom.uuid_v7 }

  def csv(lines, header: "nombre;telefono;correo") = ([ header ] + lines).join("\r\n") + "\r\n"

  def people(count) = Array.new(count) { |index| format("Persona %d;8800 %04d;", index, index + 1) }

  def call(bytes, kind: "customers")
    with_tenant(organization) do
      described_class.call(kind:, bytes:, company_id: company.id, branch_id: branch.id, created_by_id: user_id)
    end
  end

  it "con 100 filas y 3 teléfonos inválidos deja 97 listas y 3 rechazadas con su motivo" do
    lines = people(100)
    [ 10, 50, 99 ].each { |index| lines[index] = "Mal #{index};123;" }

    batch = call(csv(lines))

    rejected = with_tenant(organization) { batch.rows.where(status: "rejected").map { [ it.row_number, it.error_codes ] } }
    expect([ batch.total_count, batch.ready_count, batch.rejected_count ]).to eq([ 100, 97, 3 ])
    expect(rejected).to eq([ [ 12, { "telefono" => "invalid" } ], [ 52, { "telefono" => "invalid" } ], [ 101, { "telefono" => "invalid" } ] ])
  end

  it "rechaza la segunda aparición de un teléfono dentro del archivo aunque venga en otro formato" do
    batch = call(csv([ "Ana;8800 0001;", "Ana bis;+505 8800-0001;" ]))

    expect(with_tenant(organization) { batch.rows.map { [ it.row_number, it.status, it.error_codes ] } })
      .to eq([ [ 2, "ready", {} ], [ 3, "rejected", { "telefono" => "duplicate_in_file" } ] ])
  end

  it "no escribe clientes: solo previsualiza" do
    expect { call(csv(people(3))) }.not_to(change { with_tenant(organization) { Customers::Customer.count } })
  end

  it "guarda las celdas cifradas y queda pendiente de confirmar hasta su vencimiento" do
    freeze_time do
      batch = call(csv([ "Ana;8800 0001;ana@ejemplo.com" ]))

      raw = ApplicationRecord.connection.select_value("SELECT payload FROM import_rows WHERE import_batch_id = #{ApplicationRecord.connection.quote(batch.id)}")
      expect(raw).not_to include("ana@ejemplo.com")
      expect(with_tenant(organization) { batch.rows.first.cells }).to eq("nombre" => "Ana", "telefono" => "8800 0001", "correo" => "ana@ejemplo.com")
      expect([ batch.status, batch.expires_at, batch.created_by_id, batch.branch_id ]).to eq([ "previewed", 24.hours.from_now, user_id, branch.id ])
    end
  end

  it "ignora las columnas que el importador no conoce y no las guarda" do
    batch = call(csv([ "Ana;8800 0001;;secreto" ], header: "nombre;telefono;correo;otra"))

    expect(with_tenant(organization) { batch.rows.first.cells.keys }).to eq(%w[nombre telefono correo])
  end

  it "avisa que el consentimiento del archivo no se registra" do
    batch = call(csv([ "Ana;8800 0001;si" ], header: "nombre;telefono;consentimiento_recordatorios"))

    expect(batch.warnings).to eq([ "consent_not_recorded" ])
  end

  it "rechaza un archivo sin las columnas obligatorias, nombrándolas" do
    expect { call(csv([ "Ana" ], header: "nombre")) }.to raise_error(Imports::MissingColumns) { expect(it.columns).to eq(%w[telefono]) }
  end

  it "rechaza un archivo con más de 5000 filas sin crear el lote" do
    expect { call(csv(people(5001))) }.to raise_error(Imports::TooManyRows)
    expect(with_tenant(organization) { Imports::Batch.count }).to eq(0)
  end

  it "rechaza un tipo que nadie registró" do
    expect { call(csv(people(1)), kind: "invoices") }.to raise_error(Imports::UnknownKind)
  end
end

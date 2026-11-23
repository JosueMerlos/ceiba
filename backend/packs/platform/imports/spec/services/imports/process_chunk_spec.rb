require "rails_helper"

RSpec.describe Imports::ProcessChunk do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:user_id) { SecureRandom.uuid_v7 }

  def csv(count, offset: 0)
    ([ "nombre;telefono" ] + Array.new(count) { |index| format("Persona %d;8800 %04d", index, index + offset + 1) }).join("\n")
  end

  def upload(bytes)
    with_tenant(organization) { Imports::CreateBatch.call(kind: "customers", bytes:, company_id: company.id, branch_id: branch.id, created_by_id: user_id) }
  end

  def confirm(batch, mode: "skip") = with_tenant(organization) { Imports::ConfirmBatch.call(batch: batch.reload, duplicate_mode: mode) }

  def process(batch) = with_tenant(organization) { described_class.call(batch_id: batch.id) }

  def drain(batch)
    10.times do
      process(batch)
      break unless with_tenant(organization) { batch.reload.running? }
    end
    with_tenant(organization) { batch.reload }
  end

  def chunk_events(batch)
    with_tenant(organization) { Events::OutboxEvent.where(name: "platform.import_chunk_requested.v1").select { it.payload["import_batch_id"] == batch.id }.size }
  end

  def customers_count = with_tenant(organization) { Customers::Customer.where(company_id: company.id).count }

  describe Imports::ConfirmBatch do
    it "encola el lote con el modo elegido, publica el primer tramo y audita la confirmación" do
      batch = upload(csv(3))

      confirm(batch)

      expect([ batch.reload.status, batch.duplicate_mode, batch.confirmed_at.present? ]).to eq([ "queued", "skip", true ])
      expect(chunk_events(batch)).to eq(1)
      expect(with_tenant(organization) { Audit::Event.where(action: "import.confirmed", auditable_id: batch.id).pluck(:metadata) })
        .to eq([ { "kind" => "customers", "duplicate_mode" => "skip", "ready_count" => 3 } ])
    end

    it "no se confirma dos veces" do
      batch = upload(csv(1))
      confirm(batch)

      expect { confirm(batch) }.to raise_error(Imports::NotConfirmable)
      expect(chunk_events(batch)).to eq(1)
    end

    it "no se confirma una previsualización vencida" do
      batch = upload(csv(1))

      travel(Imports::Batch::PREVIEW_TTL + 1.second) { expect { confirm(batch) }.to raise_error(Imports::NotConfirmable) }
    end

    it "rechaza un modo que el tipo no admite" do
      expect { confirm(upload(csv(1)), mode: "merge") }.to raise_error(Imports::DuplicateModeNotAllowed)
    end

    it "rechaza confirmar un lote sin filas listas" do
      batch = upload("nombre;telefono\nAna;12\n")

      expect { confirm(batch) }.to raise_error(Imports::NothingToImport)
    end

    it "no deja correr dos lotes del mismo tipo a la vez en la empresa" do
      confirm(upload(csv(1)))
      second = upload(csv(1, offset: 10))

      expect { confirm(second) }.to raise_error(Imports::AlreadyRunning)
      expect(second.reload.status).to eq("previewed")
    end
  end

  it "procesa por tramos: cada entrega aplica un tramo, deja el progreso visible y pide el siguiente" do
    stub_const("Imports::ProcessChunk::CHUNK_SIZE", 2)
    batch = upload(csv(5))
    confirm(batch)

    process(batch)

    expect([ batch.reload.status, batch.created_count, batch.ready_count ]).to eq([ "processing", 2, 3 ])
    expect(chunk_events(batch)).to eq(2)
  end

  context "al terminar" do
    def drain_mixed
      stub_const("Imports::ProcessChunk::CHUNK_SIZE", 2)
      drain(upload("nombre;telefono\nAna;8800 0001\nMal;12\nBea;8800 0002\nCarla;8800 0003\n").tap { confirm(it) })
    end

    it "cuenta cada resultado y conserva solo los códigos de las rechazadas" do
      done = drain_mixed

      expect([ done.status, done.created_count, done.rejected_count, done.ready_count, done.finished_at.present? ]).to eq([ "completed", 3, 1, 0, true ])
      expect(with_tenant(organization) { done.rows.where(status: "rejected").pluck(:error_codes) }).to eq([ { "telefono" => "invalid" } ])
    end

    it "borra el contenido de todas las filas y audita como quien confirmó" do
      done = drain_mixed

      expect(with_tenant(organization) { done.rows.pluck(:payload).compact }).to be_empty
      expect(with_tenant(organization) { Audit::Event.where(action: %w[customer.created import.completed]).pluck(:actor_type, :actor_id).uniq }).to eq([ [ "user", user_id ] ])
    end
  end

  it "importar dos veces el mismo archivo con saltar duplicados no duplica clientes" do
    first = drain(upload(csv(20)).tap { confirm(it) })
    second = drain(upload(csv(20)).tap { confirm(it) })

    expect(customers_count).to eq(20)
    expect([ first.created_count, second.created_count, second.skipped_count ]).to eq([ 20, 0, 20 ])
  end

  it "una entrega repetida de un tramo ya aplicado no aplica ni cuenta de nuevo" do
    batch = upload(csv(3))
    confirm(batch)
    done = drain(batch)

    process(batch)

    expect([ customers_count, done.reload.created_count, done.status ]).to eq([ 3, 3, "completed" ])
  end

  it "ignora un lote que no está en curso o que no existe" do
    batch = upload(csv(1))

    process(batch)
    with_tenant(organization) { described_class.call(batch_id: SecureRandom.uuid_v7) }

    expect([ batch.reload.status, customers_count ]).to eq([ "previewed", 0 ])
  end
end

require "rails_helper"

RSpec.describe Imports::Purge do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:confirmed) { { duplicate_mode: "skip", confirmed_by_id: SecureRandom.uuid_v7 } }

  def batch_in(org, **attributes)
    with_tenant(org) do
      batch = create(:import_batch, branch: create(:branch), **attributes)
      create(:import_row, batch:, row_number: 2, status: "ready")
      create(:import_row, batch:, row_number: 3, status: "rejected", error_codes: { "telefono" => "invalid" })
      batch.tap(&:refresh_counts!)
    end
  end

  def state(org, batch) = with_tenant(org) { [ batch.reload.status, batch.rows.count, batch.rows.where.not(payload: nil).count ] }

  def purge(org, batch) = with_tenant(org) { described_class.call(batch_id: batch.id) }

  describe ".due" do
    it "lista cada lote vencido o atascado con su organización, sin contexto de tenant" do
      expired = batch_in(organization, expires_at: 1.minute.ago)
      stuck = batch_in(other_organization, status: "queued", confirmed_at: 25.hours.ago, expires_at: 2.days.ago, **confirmed)
      batch_in(create(:organization), expires_at: 1.minute.from_now)

      expect(described_class.due).to contain_exactly([ organization.id, expired.id ], [ other_organization.id, stuck.id ])
    end
  end

  describe ".call" do
    it "vence la previsualización sin confirmar, borra sus filas y conserva sus conteos" do
      batch = batch_in(organization, expires_at: 1.minute.ago)

      purge(organization, batch)

      expect(state(organization, batch)).to eq([ "expired", 0, 0 ])
      expect(with_tenant(organization) { batch.reload.slice(:total_count, :ready_count, :rejected_count) })
        .to eq("total_count" => 2, "ready_count" => 1, "rejected_count" => 1)
    end

    it "no toca un lote que se confirmó después de leerse como vencido" do
      batch = batch_in(organization, expires_at: 1.minute.ago)
      with_tenant(organization) { batch.update!(status: "queued", confirmed_at: 2.minutes.ago, **confirmed) }

      purge(organization, batch)

      expect(state(organization, batch)).to eq([ "queued", 2, 2 ])
    end

    it "no toca una previsualización vigente" do
      current = batch_in(organization, expires_at: 1.minute.from_now)

      purge(organization, current)

      expect(state(organization, current)).to eq([ "previewed", 2, 2 ])
    end

    it "cierra como fallido un lote atascado más de un día tras confirmarse y borra el contenido de sus filas" do
      stuck = batch_in(organization, status: "processing", confirmed_at: 25.hours.ago, expires_at: 2.days.ago, **confirmed)

      freeze_time do
        purge(organization, stuck)

        expect(state(organization, stuck)).to eq([ "failed", 2, 0 ])
        expect(with_tenant(organization) { [ stuck.finished_at, stuck.failed_count, stuck.rows.where(status: "failed").pluck(:error_codes) ] })
          .to eq([ Time.current, 1, [ { "base" => "timeout" } ] ])
      end
    end

    it "no toca un lote en curso reciente ni uno terminado" do
      running = batch_in(organization, status: "processing", confirmed_at: 1.hour.ago, expires_at: 2.days.ago, **confirmed)
      finished = batch_in(organization, status: "completed", confirmed_at: 3.days.ago, finished_at: 3.days.ago, expires_at: 4.days.ago, **confirmed)

      [ running, finished ].each { purge(organization, it) }

      expect([ state(organization, running), state(organization, finished) ]).to eq([ [ "processing", 2, 2 ], [ "completed", 2, 2 ] ])
    end
  end

  describe Imports::PurgeExpiredJob do
    it "encola una purga por lote, cada una en el tenant de su organización" do
      mine = batch_in(organization, expires_at: 1.minute.ago)
      theirs = batch_in(other_organization, expires_at: 1.minute.ago)

      described_class.new.perform

      expect(Imports::PurgeBatchJob.jobs.map { [ it["organization_id"], it["args"] ] })
        .to contain_exactly([ organization.id, [ mine.id ] ], [ other_organization.id, [ theirs.id ] ])
      Imports::PurgeBatchJob.drain
      expect([ state(organization, mine), state(other_organization, theirs) ]).to eq([ [ "expired", 0, 0 ], [ "expired", 0, 0 ] ])
    end
  end
end

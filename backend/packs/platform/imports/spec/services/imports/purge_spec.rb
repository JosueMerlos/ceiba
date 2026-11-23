require "rails_helper"

RSpec.describe Imports::Purge do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def batch_in(org, **attributes)
    with_tenant(org) do
      batch = create(:import_batch, branch: create(:branch), **attributes)
      create(:import_row, batch:, row_number: 2, status: "ready")
      create(:import_row, batch:, row_number: 3, status: "rejected", error_codes: { "telefono" => "invalid" })
      batch
    end
  end

  def state(org, batch) = with_tenant(org) { [ batch.reload.status, batch.rows.count, batch.rows.where.not(payload: nil).count ] }

  def purge(org) = with_tenant(org) { described_class.call }

  describe ".due_organization_ids" do
    it "encuentra las organizaciones con algo vencido, sin contexto de tenant y sin repetirlas" do
      batch_in(organization, expires_at: 1.minute.ago)
      batch_in(organization, expires_at: 2.minutes.ago)
      batch_in(other_organization, status: "queued", duplicate_mode: "skip", confirmed_at: 25.hours.ago, expires_at: 2.days.ago)
      batch_in(create(:organization), expires_at: 1.minute.from_now)

      expect(described_class.due_organization_ids).to contain_exactly(organization.id, other_organization.id)
    end
  end

  describe ".call" do
    it "vence la previsualización sin confirmar y borra sus filas" do
      batch = batch_in(organization, expires_at: 1.minute.ago)

      purge(organization)

      expect(state(organization, batch)).to eq([ "expired", 0, 0 ])
    end

    it "no toca una previsualización vigente ni la de otra organización" do
      current = batch_in(organization, expires_at: 1.minute.from_now)
      theirs = batch_in(other_organization, expires_at: 1.minute.ago)

      purge(organization)

      expect([ state(organization, current), state(other_organization, theirs) ]).to eq([ [ "previewed", 2, 2 ], [ "previewed", 2, 2 ] ])
    end

    it "cierra como fallido un lote atascado más de un día tras confirmarse y borra el contenido de sus filas" do
      stuck = batch_in(organization, status: "processing", duplicate_mode: "skip", confirmed_at: 25.hours.ago, expires_at: 2.days.ago)

      freeze_time do
        purge(organization)

        expect(state(organization, stuck)).to eq([ "failed", 2, 0 ])
        expect(with_tenant(organization) { [ stuck.finished_at, stuck.failed_count, stuck.rows.where(status: "failed").pluck(:error_codes) ] })
          .to eq([ Time.current, 1, [ { "base" => "timeout" } ] ])
      end
    end

    it "no toca un lote en curso reciente ni uno terminado" do
      running = batch_in(organization, status: "processing", duplicate_mode: "skip", confirmed_at: 1.hour.ago, expires_at: 2.days.ago)
      finished = batch_in(organization, status: "completed", duplicate_mode: "skip", confirmed_at: 3.days.ago, finished_at: 3.days.ago, expires_at: 4.days.ago)

      purge(organization)

      expect([ state(organization, running), state(organization, finished) ]).to eq([ [ "processing", 2, 2 ], [ "completed", 2, 2 ] ])
    end
  end

  describe Imports::PurgeExpiredJob do
    it "encola una purga por organización con su organization_id, que corre dentro de ese tenant" do
      batch = batch_in(organization, expires_at: 1.minute.ago)

      described_class.new.perform

      expect(Imports::PurgeOrganizationJob.jobs.map { it["organization_id"] }).to eq([ organization.id ])
      Imports::PurgeOrganizationJob.drain
      expect(state(organization, batch)).to eq([ "expired", 0, 0 ])
    end
  end
end

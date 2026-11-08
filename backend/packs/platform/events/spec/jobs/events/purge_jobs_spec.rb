require "rails_helper"

RSpec.describe "Jobs de purga del outbox" do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  def outbox_ids(org) = with_tenant(org) { Events::OutboxEvent.pluck(:id) }
  def processed_ids(org) = with_tenant(org) { Events::ProcessedEvent.pluck(:id) }

  it "son jobs del sistema (tenant: false) de la cola low" do
    [ Events::PurgeOutboxJob, Events::PurgeProcessedJob ].each do |job|
      expect(job.get_sidekiq_options).to include("queue" => "low", "tenant" => false)
    end
  end

  it "la retención es de 30 días" do
    expect(Events::Purge::RETENTION).to eq(30.days)
  end

  describe Events::PurgeOutboxJob do
    it "borra los eventos PUBLICADOS hace más de 30 días, de todas las organizaciones" do
      old_a = create_in(organization, :outbox_event, published_at: 31.days.ago)
      old_b = create_in(other, :outbox_event, published_at: 45.days.ago)

      described_class.new.perform

      expect([ outbox_ids(organization), outbox_ids(other) ]).to eq([ [], [] ])
      expect([ old_a, old_b ]).to all(be_present)
    end

    it "conserva los publicados recientes y NUNCA borra un pendiente, por antiguo que sea" do
      recent = create_in(organization, :outbox_event, published_at: 29.days.ago)
      pending = create_in(organization, :outbox_event, published_at: nil, created_at: 90.days.ago)

      described_class.new.perform

      expect(outbox_ids(organization)).to contain_exactly(recent.id, pending.id)
    end

    it "borra por lotes hasta vaciar lo purgable" do
      stub_const("Events::Purge::BATCH_SIZE", 2)
      5.times { create_in(organization, :outbox_event, published_at: 40.days.ago) }
      keep = create_in(organization, :outbox_event, published_at: 1.day.ago)

      described_class.new.perform

      expect(outbox_ids(organization)).to eq([ keep.id ])
    end
  end

  describe Events::PurgeProcessedJob do
    it "borra los processed_events de más de 30 días, de todas las organizaciones, y conserva los recientes" do
      create_in(organization, :processed_event, processed_at: 31.days.ago)
      create_in(other, :processed_event, processed_at: 60.days.ago)
      recent = create_in(organization, :processed_event, processed_at: 5.days.ago)

      described_class.new.perform

      expect([ processed_ids(organization), processed_ids(other) ]).to eq([ [ recent.id ], [] ])
    end
  end
end

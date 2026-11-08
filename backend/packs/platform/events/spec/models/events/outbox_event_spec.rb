require "rails_helper"

RSpec.describe Events::OutboxEvent do
  let(:organization) { create(:organization) }

  def build_event(**attributes) = build(:outbox_event, **attributes)

  it "es un modelo tenant con la organización del contexto" do
    with_tenant(organization) do
      expect(create(:outbox_event).organization_id).to eq(organization.id)
    end
  end

  it "acepta un nombre con la forma <modulo>.<hecho>.v<N>" do
    with_tenant(organization) { expect(build_event(name: "platform.organization_provisioned.v1")).to be_valid }
  end

  it "rechaza nombres sin esa forma" do
    with_tenant(organization) do
      invalid = [ "sin_forma", "platform.hecho", "Platform.Hecho.v1" ].map { |name| build_event(name:).valid? }

      expect(invalid).to eq([ false, false, false ])
    end
  end

  describe ".pending y .published" do
    it "separan los eventos sin publicar de los publicados" do
      with_tenant(organization) do
        pending_event = create(:outbox_event)
        published_event = create(:outbox_event, published_at: 1.minute.ago)

        expect(described_class.pending).to contain_exactly(pending_event)
        expect(described_class.published).to contain_exactly(published_event)
      end
    end

    it "los pendientes salen ordenados por id" do
      with_tenant(organization) do
        events = create_list(:outbox_event, 3)

        expect(described_class.pending.in_publication_order.pluck(:id)).to eq(events.map(&:id).sort)
      end
    end
  end

  describe ".purgeable" do
    it "son los publicados antes del límite; nunca los pendientes" do
      with_tenant(organization) do
        old = create(:outbox_event, published_at: 40.days.ago)
        create(:outbox_event, published_at: 1.day.ago)
        create(:outbox_event, published_at: nil, created_at: 40.days.ago)

        expect(described_class.purgeable(30.days.ago)).to contain_exactly(old)
      end
    end
  end
end

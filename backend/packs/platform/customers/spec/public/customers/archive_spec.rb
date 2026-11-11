require "rails_helper"

RSpec.describe Customers::Archive do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def events = Audit::Event.where(action: "customer.archived").to_a

  it "fija archived_at, no borra la fila y audita por id", :aggregate_failures do
    with_tenant(organization) do
      customer = create(:customer, company:)

      freeze_time do
        described_class.call(customer:)

        expect(customer.reload.archived_at).to eq(Time.current)
      end
      expect(Customers::Customer.active).to be_empty
      expect(Customers::Customer.count).to eq(1)
      expect(events.size).to eq(1)
      expect([ events.first.auditable_id, events.first.metadata ]).to eq([ customer.id, { "changed" => %w[archived_at] } ])
    end
  end

  it "archivar dos veces conserva la primera fecha y no duplica la auditoría" do
    with_tenant(organization) do
      customer = create(:customer, company:)

      freeze_time { described_class.call(customer:) }
      first = customer.reload.archived_at
      travel_to(2.days.from_now) { described_class.call(customer:) }

      expect(customer.reload.archived_at).to eq(first)
      expect(events.size).to eq(1)
    end
  end
end

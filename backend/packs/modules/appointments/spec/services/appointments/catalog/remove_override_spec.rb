require "rails_helper"

RSpec.describe Appointments::Catalog::RemoveOverride do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "borra el override y audita el antes" do
    with_tenant(organization) do
      override = create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)

      described_class.call(override:)

      expect(Appointments::BranchServiceOverride.where(id: override.id)).to be_empty
      event = events("service_override.removed").sole
      expect([ event.before, event.after ]).to eq([ { "duration_minutes" => 45, "price_minor" => 30_000 }, nil ])
    end
  end

  it "no toca el servicio ni los overrides de otras sucursales" do
    with_tenant(organization) do
      other_branch = create(:branch, company:)
      override = create(:branch_service_override, service:, branch:)
      kept = create(:branch_service_override, service:, branch: other_branch)

      described_class.call(override:)

      expect(Appointments::BranchServiceOverride.pluck(:id)).to eq([ kept.id ])
      expect(Appointments::Service.where(id: service.id)).to exist
    end
  end

  it "el bloque ve la fila ACTUAL (recargada): si otro la cambió, se autoriza contra lo vigente y, si lanza, no se borra", :aggregate_failures do
    with_tenant(organization) do
      stale = create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: nil)
      Appointments::BranchServiceOverride.where(id: stale.id).update_all(price_minor: 9_000)
      seen = nil

      expect { described_class.call(override: stale) { |current| seen = current.price_minor; raise "denied" } }.to raise_error("denied")

      expect(seen).to eq(9_000)
      expect(Appointments::BranchServiceOverride.where(id: stale.id)).to exist
      expect(events("service_override.removed")).to be_empty
    end
  end

  it "si la fila ya no existe (otra petición la quitó) lanza RecordNotFound y no audita" do
    with_tenant(organization) do
      override = create(:branch_service_override, service:, branch:)
      Appointments::BranchServiceOverride.where(id: override.id).delete_all

      expect { described_class.call(override:) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(events("service_override.removed")).to be_empty
    end
  end
end

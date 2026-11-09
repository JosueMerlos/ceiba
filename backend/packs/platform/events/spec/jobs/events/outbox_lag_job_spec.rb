require "rails_helper"

RSpec.describe Events::OutboxLagJob do
  it "es un job del sistema (tenant: false)" do
    expect(described_class.get_sidekiq_options).to include("tenant" => false)
  end

  it "reporta el lag del outbox" do
    allow(Events::OutboxLag).to receive(:report)

    described_class.new.perform

    expect(Events::OutboxLag).to have_received(:report)
  end
end

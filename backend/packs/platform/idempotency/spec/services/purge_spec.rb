require "rails_helper"

# Purge of expired keys: idempotency_keys stores responses, so it cannot grow forever or keep data beyond its usefulness
# (24 h). In batches, across all organizations (Idempotency::CrossTenant).
RSpec.describe "Purga de idempotency_keys" do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  def keys_of(org) = with_tenant(org) { Idempotency::Key.order(:id).pluck(:key) }

  it "Idempotency::PurgeExpiredJob es un job del sistema (tenant: false) de la cola low" do
    expect(Idempotency::PurgeExpiredJob.get_sidekiq_options).to include("queue" => "low", "tenant" => false)
  end

  it "borra las claves vencidas de todas las organizaciones y conserva las vigentes" do
    create_in(organization, :idempotency_key, key: "vencida-a", expires_at: 1.minute.ago)
    create_in(organization, :idempotency_key, key: "vigente-a", expires_at: 1.hour.from_now)
    create_in(other, :idempotency_key, key: "vencida-b", expires_at: 3.days.ago)

    Idempotency::PurgeExpiredJob.new.perform

    expect([ keys_of(organization), keys_of(other) ]).to eq([ [ "vigente-a" ], [] ])
  end

  it "borra por lotes hasta vaciar lo vencido" do
    stub_const("Idempotency::Purge::BATCH_SIZE", 2)
    5.times { |n| create_in(organization, :idempotency_key, key: "v-#{n}", expires_at: 2.hours.ago) }
    create_in(organization, :idempotency_key, key: "vigente", expires_at: 2.hours.from_now)

    expect(Idempotency::Purge.expired).to eq(5)
    expect(keys_of(organization)).to eq([ "vigente" ])
  end

  it "se programa a diario, de madrugada, en sidekiq-cron" do
    entry = Idempotency::Schedule.jobs.fetch("idempotency_purge_expired")

    expect(entry).to include("class" => "Idempotency::PurgeExpiredJob", "cron" => a_string_matching(/\A\d+ \d+ \* \* \*\z/))
  end

  it "load! registra el job en sidekiq-cron sin pisar los de otros packs", :redis do
    Events::Schedule.load!
    Idempotency::Schedule.load!

    expect(Sidekiq::Cron::Job.all.map(&:name)).to include("events_relay", "idempotency_purge_expired")
  ensure
    Sidekiq::Cron::Job.destroy_all!
  end
end

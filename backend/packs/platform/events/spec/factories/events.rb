FactoryBot.define do
  # Las factories tenant se usan DENTRO de un tenant (ver packs/platform/tenancy/spec/factories/tenancy.rb).
  factory :outbox_event, class: "Events::OutboxEvent" do
    organization { ActsAsTenant.current_tenant }
    name { "platform.organization_provisioned.v1" }
    payload { {} }
    metadata { {} }
    occurred_at { Time.current }
  end

  factory :processed_event, class: "Events::ProcessedEvent" do
    organization { ActsAsTenant.current_tenant }
    event_id { SecureRandom.uuid }
    sequence(:subscriber) { |n| "test.suscriptor_#{n}" }
    processed_at { Time.current }
  end
end

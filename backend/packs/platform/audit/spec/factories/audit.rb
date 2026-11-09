FactoryBot.define do
  # Tenant: se usa DENTRO de un tenant (ver packs/platform/tenancy/spec/factories/tenancy.rb).
  factory :audit_event, class: "Audit::Event" do
    organization { ActsAsTenant.current_tenant }
    actor_type { "system" }
    action { "probe.created" }
    auditable_type { "Probe" }
    auditable_id { SecureRandom.uuid }
    created_at { Time.current }
  end
end

FactoryBot.define do
  # Tenant factories: use them INSIDE a tenant.
  factory :audit_event, class: "Audit::Event" do
    organization { ActsAsTenant.current_tenant }
    actor_type { "system" }
    action { "probe.created" }
    auditable_type { "Probe" }
    auditable_id { SecureRandom.uuid }
    created_at { Time.current }
  end
end

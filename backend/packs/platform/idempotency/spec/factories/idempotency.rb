FactoryBot.define do
  # Tenant factories: use them INSIDE a tenant.
  factory :idempotency_key, class: "Idempotency::Key" do
    organization { ActsAsTenant.current_tenant }
    principal_key { "anonymous" }
    sequence(:key) { |n| "clave-#{n}" }
    request_fingerprint { SecureRandom.hex(32) }
    expires_at { 24.hours.from_now }
  end
end

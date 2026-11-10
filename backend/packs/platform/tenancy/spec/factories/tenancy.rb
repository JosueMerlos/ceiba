FactoryBot.define do
  factory :organization, class: "Tenancy::Organization" do
    sequence(:name) { |n| "Organización #{n}" }
  end

  # Tenant factories are used INSIDE a tenant (`with_tenant(org) { create(:company) }` or `create_in(org, :company)`):
  # building a tenant model without one fails by design, and a factory is not a bypass. A company's organization is the
  # active tenant.
  factory :company, class: "Tenancy::Company" do
    organization { ActsAsTenant.current_tenant }
    sequence(:name) { |n| "Empresa #{n}" }
    sequence(:slug) { |n| "empresa-#{n}" }
    business_type { "salon" }
    currency { "NIO" }
  end

  # organization_id comes from the COMPANY, never generated separately: the composite FK demands it.
  factory :branch, class: "Tenancy::Branch" do
    company
    organization { company.organization }
    sequence(:name) { |n| "Sucursal #{n}" }
    time_zone { "America/Managua" }
  end
end
